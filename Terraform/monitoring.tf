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