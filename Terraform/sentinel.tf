resource "azurerm_sentinel_log_analytics_workspace_onboarding" "law-sentinal" {
  workspace_id = azurerm_log_analytics_workspace.lab-law.id
}

resource "azurerm_sentinel_alert_rule_scheduled" "name" {
  name                       = "6bda0e6e-ffa6-47c7-b5de-36cfd9977c86"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab-law.id
  display_name               = "NSG-config-change"
  severity                   = "Low"
  enabled                    = true
  query_frequency            = "PT5M"
  query_period               = "PT30M"
  trigger_operator           = "GreaterThan"
  trigger_threshold          = 0
  description                = "Detects successful NSG configuration changes. Investigate authorization and potential network exposure."

  custom_details = {
    NSGName       = "NSGName"
    ResourceGroup = "ResourceGroup"
    ResourceId    = "ResourcePath"
    Actor         = "Caller"
    CallerIP      = "CallerIpAddress"
    Operation     = "OperationNameValue"
    RuleName      = "RuleName"
    EventTimeUTC  = "EventTimeUTC"
    CorrelationId = "CorrelationId"
  }

  alert_details_override {
    display_name_format = "NSG configuration changed: {{NSGName}}"
    description_format  = "Actor {{Caller}} performed {{OperationNameValue}} at {{EventTimeUTC}} UTC. Review custom details and approved-change evidence."
  }

  entity_mapping {
    entity_type = "AzureResource"

    field_mapping {
      identifier  = "ResourceId"
      column_name = "ResourcePath"
    }
  }

  event_grouping {
    aggregation_method = "AlertPerResult"
  }
  query = <<QUERY
  AzureActivity
  | where ResourceGroup =~ "rg-azure-infra-security-lab"
  | where ActivityStatusValue =~ "Success"
  | where ingestion_time() > ago(5m)
  | where OperationNameValue in~ (
      "Microsoft.Network/networkSecurityGroups/write",
      "Microsoft.Network/networkSecurityGroups/securityRules/write",
      "Microsoft.Network/networkSecurityGroups/securityRules/delete"
  )
  | extend ResourcePath = coalesce(
      _ResourceId,
      ResourceId,
      tostring(Authorization_d.scope)
  )
  | extend NSGName = coalesce(
      extract(@"(?i)/networksecuritygroups/([^/]+)", 1, ResourcePath),
      "Unidentified NSG"
  )
  | extend RuleName = coalesce(
      extract(@"(?i)/securityrules/([^/]+)", 1, ResourcePath),
      "NSG-level operation"
  )
  | extend EventTimeUTC =
      format_datetime(TimeGenerated, "yyyy-MM-dd HH:mm:ss")
  | project TimeGenerated, EventTimeUTC, NSGName, RuleName,
            ResourceGroup, ResourcePath, Caller, CallerIpAddress,
            OperationNameValue, ActivityStatusValue, CorrelationId
QUERY
  incident {
    create_incident_enabled = true
    grouping {
      enabled = false
    }
  }
}


resource "azurerm_sentinel_alert_rule_scheduled" "ssh_failures" {
  name                       = "d4715378-1d2c-4dd8-a4be-c462bc245fe1"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab-law.id
  display_name               = "Repeated failed SSH authentication"
  description                = "Detects five or more invalid-username or failed-password records from one source IP against one VM within 30 minutes."
  severity                   = "Medium"
  enabled                    = true

  query_frequency   = "PT5M"
  query_period      = "PT30M"
  trigger_operator  = "GreaterThan"
  trigger_threshold = 0

  query = <<-QUERY
    Syslog
    | where TimeGenerated > ago(30m)
    | where ProcessName in ("sshd", "sshd-session")
    | where SyslogMessage startswith "Invalid user "
        or (
            SyslogMessage startswith "Failed password for "
            and SyslogMessage !startswith "Failed password for invalid user "
        )
    | extend RemoteIP = extract(@"from (\S+) port", 1, SyslogMessage)
    | where isnotempty(RemoteIP)
    | extend IngestedAt = ingestion_time()
    | summarize
        FailureCount = count(),
        LastSeen = max(TimeGenerated),
        LatestIngestion = max(IngestedAt)
        by Computer, RemoteIP
    | where FailureCount >= 5
    | where LatestIngestion > ago(5m)
    | extend TimeGenerated = LastSeen
  QUERY

  entity_mapping {
    entity_type = "Host"

    field_mapping {
      identifier  = "HostName"
      column_name = "Computer"
    }
  }

  entity_mapping {
    entity_type = "IP"

    field_mapping {
      identifier  = "Address"
      column_name = "RemoteIP"
    }
  }

  event_grouping {
    aggregation_method = "AlertPerResult"
  }

  incident {
    create_incident_enabled = true

    grouping {
      enabled = false
    }
  }
}

resource "azurerm_logic_app_workflow" "dns_rep" {
  name                = var.la-name
  resource_group_name = var.rg-lab
  location            = var.location

  identity {
    type = "SystemAssigned"
  }

  workflow_parameters = {
    "$connections" = jsonencode({
      type         = "Object"
      defaultValue = {}
    })
  }

  parameters = {
    "$connections" = jsonencode({
      virustotal = {
        id             = data.azurerm_managed_api.virustotal.id
        connectionId   = azurerm_api_connection.VT-API.id
        connectionName = azurerm_api_connection.VT-API.name
      }
    })
  }
}

resource "azurerm_logic_app_trigger_recurrence" "dns_rep_recur" {
  name         = "Every_Five_Mins"
  logic_app_id = azurerm_logic_app_workflow.dns_rep.id
  frequency    = "Minute"
  interval     = 5
}

resource "azurerm_logic_app_action_custom" "query_dns" {
  name         = "Query_DNS_Logs"
  logic_app_id = azurerm_logic_app_workflow.dns_rep.id

  body = jsonencode({
    type     = "Http"
    runAfter = {}

    inputs = {
      method = "POST"
      uri    = "https://api.loganalytics.io/v1/workspaces/${azurerm_log_analytics_workspace.lab-law.workspace_id}/query"

      headers = {
        "Content-Type" = "application/json"
      }

      authentication = {
        type     = "ManagedServiceIdentity"
        audience = "https://api.loganalytics.io"
      }

      body = {
        timespan = "PT30M"

        query = <<-KQL
          Syslog
          | where TimeGenerated > ago(30m)
          | where ingestion_time() > ago(5m)
          | where Computer == "vm-lab-test-01"
          | where ProcessName contains "unbound"
          | parse SyslogMessage with * "info: " ClientIP:string " " QueriedDomain:string " " QueryType:string " IN" *
          | where isnotempty(ClientIP) and isnotempty(QueriedDomain)
          | extend QueriedDomain = trim_end(@"\.", tolower(QueriedDomain))
          | summarize
              FirstSeen = min(TimeGenerated),
              LastSeen = max(TimeGenerated),
              ClientIPs = make_set(ClientIP, 20)
              by QueriedDomain
          | project QueriedDomain, FirstSeen, LastSeen, ClientIPs
        KQL
      }
    }
  })
}

resource "azurerm_logic_app_action_custom" "check_domains" {
  name         = "Check_Domains"
  logic_app_id = azurerm_logic_app_workflow.dns_rep.id

  body = jsonencode({
    type = "Foreach"

    # Start with one domain per run while testing the connection.
    foreach = "@take(body('Query_DNS_Logs')['tables'][0]['rows'], 1)"

    runAfter = {
      Query_DNS_Logs = ["Succeeded"]
    }

    runtimeConfiguration = {
      concurrency = {
        repetitions = 1
      }
    }

    actions = {
      Get_Domain_Report = {
        type     = "ApiConnection"
        runAfter = {}

        inputs = {
          host = {
            connection = {
              name = "@parameters('$connections')['virustotal']['connectionId']"
            }
          }

          method = "get"
          path   = "/api/v3/domains/@{encodeURIComponent(items('Check_Domains')[0])}"
        }
      }

      # The workflow identity receives Sentinel Responder through portal IAM.
      Flagged_Domain = {
        type = "If"
        runAfter = {
          Get_Domain_Report = ["Succeeded"]
        }
        expression = "@or(greater(int(coalesce(body('Get_Domain_Report')?['attributes']?['last_analysis_stats']?['malicious'], 0)), 0), greater(int(coalesce(body('Get_Domain_Report')?['attributes']?['last_analysis_stats']?['suspicious'], 0)), 0))"

        actions = {
          # Generate once so HTTP retries reuse the same incident ID.
          Incident_ID = {
            type     = "Compose"
            inputs   = "@guid()"
            runAfter = {}
          }

          Create_Incident = {
            type = "Http"
            runAfter = {
              Incident_ID = ["Succeeded"]
            }
            inputs = {
              method = "PUT"
              uri    = "https://management.azure.com${azurerm_log_analytics_workspace.lab-law.id}/providers/Microsoft.SecurityInsights/incidents/@{outputs('Incident_ID')}?api-version=2025-09-01"
              headers = {
                "Content-Type" = "application/json"
              }
              authentication = {
                type     = "ManagedServiceIdentity"
                audience = "https://management.azure.com/"
              }
              body = {
                properties = {
                  title                = "DNS reputation flagged: @{items('Check_Domains')[0]}"
                  severity             = "Medium"
                  status               = "New"
                  description          = "Domain: @{items('Check_Domains')[0]}. Client IPs: @{items('Check_Domains')[3]}. Malicious verdicts: @{body('Get_Domain_Report')['attributes']['last_analysis_stats']['malicious']}. Suspicious verdicts: @{body('Get_Domain_Report')['attributes']['last_analysis_stats']['suspicious']}. VirusTotal report: https://www.virustotal.com/gui/domain/@{encodeURIComponent(items('Check_Domains')[0])}. Workflow run: @{workflow().run.name}. A DNS lookup and reputation verdict do not prove compromise."
                  firstActivityTimeUtc = "@items('Check_Domains')[1]"
                  lastActivityTimeUtc  = "@items('Check_Domains')[2]"
                }
              }
            }
          }
        }
        else = { actions = {} }
      }

    }
  })

  depends_on = [
    azurerm_logic_app_action_custom.query_dns
  ]
}

data "azurerm_managed_api" "virustotal" {
  name     = "virustotal"
  location = var.location
}

resource "azurerm_api_connection" "VT-API" {
  name                = "Virus-Total-API"
  resource_group_name = var.rg-lab
  managed_api_id      = data.azurerm_managed_api.virustotal.id
  display_name        = "VirusTotal domain reputation"

  parameter_values = {
    "api_key" = var.VTKey
  }
}
