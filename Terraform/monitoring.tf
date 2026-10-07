resource "azurerm_log_analytics_workspace" "lab-law" {
  name                = "law-azure-sec-lab"
  resource_group_name = var.rg-lab
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 1
}

data "azurerm_subscription" "current" {}

resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  name                       = "diag-activity-log-lab"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab-law.id

  enabled_log {
    category = "Administrative"
  }
}

resource "azurerm_monitor_data_collection_rule" "linux_syslog" {
  name                = "dcr-lab-linux-syslog"
  location            = azurerm_virtual_network.vnets["primary"].location
  resource_group_name = var.rg-lab
  kind                = "Linux"

  destinations {
    log_analytics {
      name                  = "lab-workspace"
      workspace_resource_id = azurerm_log_analytics_workspace.lab-law.id
    }
  }

  data_sources {
    syslog {
      name           = "linux-events"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["auth", "authpriv", "daemon", "syslog"]
      log_levels = [
        "Info",
        "Notice",
        "Warning",
        "Error",
        "Critical",
        "Alert",
        "Emergency"
      ]
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["lab-workspace"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "linux_syslog" {
  for_each = azurerm_virtual_machine_extension.ama

  name                    = "dcra-lab-syslog"
  target_resource_id      = azurerm_linux_virtual_machine.linux_vms[each.key].id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.linux_syslog.id
}

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
