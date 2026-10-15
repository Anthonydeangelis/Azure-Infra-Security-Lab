resource "azurerm_sentinel_log_analytics_workspace_onboarding" "law-sentinal" {
  workspace_id = azurerm_log_analytics_workspace.lab-law.id
}

resource "azurerm_sentinel_alert_rule_scheduled" "nsg-config" {
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
    description_format  = "Actor {{Caller}} performed {{OperationNameValue}} at {{EventTimeUTC}} UTC. Review NSG, caller IP, and correlation ID in custom details."
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
    | extend AttemptedUser = coalesce(
        extract(@"^Invalid user (\S+) from ", 1, SyslogMessage),
        extract(@"^Failed password for (\S+) from ", 1, SyslogMessage)
      )
    | extend IngestedAt = ingestion_time()
    | summarize
        FailureCount = count(),
        InvalidUserCount = countif(SyslogMessage startswith "Invalid user "),
        FailedPasswordCount = countif(SyslogMessage startswith "Failed password for "),
        AttemptedUsers = make_set(AttemptedUser, 20),
        FirstSeen = min(TimeGenerated),
        LastSeen = max(TimeGenerated),
        LatestIngestion = max(IngestedAt)
        by Computer, RemoteIP
    | where FailureCount >= 5
    | where LatestIngestion > ago(5m)
    | extend TimeGenerated = LastSeen,
             Usernames = strcat_array(AttemptedUsers, ", "),
             FirstSeenUTC = format_datetime(FirstSeen, "yyyy-MM-dd HH:mm:ss"),
             LastSeenUTC = format_datetime(LastSeen, "yyyy-MM-dd HH:mm:ss")
  QUERY

  custom_details = {
    Host                = "Computer"
    SourceIP            = "RemoteIP"
    MatchingRecords     = "FailureCount"
    InvalidUserRecords  = "InvalidUserCount"
    FailedPasswordCount = "FailedPasswordCount"
    AttemptedUsers      = "Usernames"
    FirstSeenUTC        = "FirstSeenUTC"
    LastSeenUTC         = "LastSeenUTC"
  }

  alert_details_override {
    display_name_format = "Repeated failed SSH authentication on {{Computer}}"
    description_format  = "Source {{RemoteIP}} generated {{FailureCount}} matching SSH records on {{Computer}}. Review usernames, record types, and timestamps in custom details; records are not guaranteed unique login attempts."
  }

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
          // Temporary deterministic test: other domains remain in Syslog but skip VT.
          | where QueriedDomain == "linkcoll.net"
          // Skip only the observed monitoring hostnames; retain their raw Syslog records.
          | where QueriedDomain !in~ (
              "39466a12-2923-41bf-a682-9a9ebda8afc2.ods.opinsights.azure.com",
              "ipv4-eus2-oi-ods-cses-a.eastus2.cloudapp.azure.com",
              "ipv4-eus2-oi-ods-cses-b.eastus2.cloudapp.azure.com",
              "ipv4-eus2-oi-ods-cses-d.eastus2.cloudapp.azure.com",
              "global.handler.control.monitor.azure.com",
              "sfmc-amcs-prod-eus-1-handler.eastus.cloudapp.azure.com",
              "api.loganalytics.io"
          )
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
      Flagged_Domain = {
        type = "If"
        runAfter = {
          Get_Domain_Report = ["Succeeded"]
        }
        expression = "@or(greater(int(coalesce(body('Get_Domain_Report')?['data']?['attributes']?['last_analysis_stats']?['malicious'], 0)), 0), greater(int(coalesce(body('Get_Domain_Report')?['data']?['attributes']?['last_analysis_stats']?['suspicious'], 0)), 0))"

        actions = {
          For_Each_Client = {
            type     = "Foreach"
            foreach  = "@json(items('Check_Domains')[3])"
            runAfter = {}
            runtimeConfiguration = {
              concurrency = { repetitions = 1 }
            }
            actions = {
              Save_Flagged_Result = {
                type     = "Http"
                runAfter = {}
                inputs = {
                  method  = "POST"
                  uri     = "${azurerm_monitor_data_collection_endpoint.dns_reputation.logs_ingestion_endpoint}/dataCollectionRules/${azurerm_monitor_data_collection_rule.dns_reputation.immutable_id}/streams/Custom-DNSReputation?api-version=2023-01-01"
                  headers = { "Content-Type" = "application/json" }
                  authentication = {
                    type     = "ManagedServiceIdentity"
                    audience = "https://monitor.azure.com"
                  }
                  body = [{
                    TimeGenerated   = "@utcNow()"
                    Domain          = "@items('Check_Domains')[0]"
                    ClientIP        = "@items('For_Each_Client')"
                    MaliciousCount  = "@int(body('Get_Domain_Report')['data']['attributes']['last_analysis_stats']['malicious'])"
                    SuspiciousCount = "@int(body('Get_Domain_Report')['data']['attributes']['last_analysis_stats']['suspicious'])"
                    DNSFirstSeen    = "@items('Check_Domains')[1]"
                    DNSLastSeen     = "@items('Check_Domains')[2]"
                    VTAnalysisEpoch = "@int(coalesce(body('Get_Domain_Report')?['data']?['attributes']?['last_analysis_date'], 0))"
                    WorkflowRunId   = "@workflow().run.name"
                  }]
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
data "azurerm_managed_api" "outlook" {
  name     = "outlook"
  location = var.location
}
resource "azurerm_api_connection" "outlook" {
  name                = "incident-email-outlook"
  resource_group_name = var.rg-lab
  managed_api_id      = data.azurerm_managed_api.outlook.id
  display_name        = "Incident email notifications"
}

resource "azurerm_logic_app_workflow" "incident_email" {
  name                = "incident-email"
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
      outlook = {
        id             = data.azurerm_managed_api.outlook.id
        connectionId   = azurerm_api_connection.outlook.id
        connectionName = azurerm_api_connection.outlook.name
      }
      azuresentinel = {
        id = data.azurerm_managed_api.sentinel.id
        connectionId = jsondecode(
          azurerm_resource_group_template_deployment.sentinel_email_connection.output_content
        ).connectionId.value
        connectionName = "incident-email-sentinel"
        connectionProperties = {
          authentication = {
            type = "ManagedServiceIdentity"
          }
        }
      }
    })
  }
}