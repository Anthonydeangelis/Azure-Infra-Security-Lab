locals {
  dns_reputation_columns = [
    { name = "TimeGenerated", type = "datetime" },
    { name = "Domain", type = "string" },
    { name = "ClientIP", type = "string" },
    { name = "MaliciousCount", type = "long" },
    { name = "SuspiciousCount", type = "long" },
    { name = "DNSFirstSeen", type = "datetime" },
    { name = "DNSLastSeen", type = "datetime" },
    { name = "VTAnalysisEpoch", type = "long" },
    { name = "WorkflowRunId", type = "string" }
  ]
}

resource "azurerm_log_analytics_workspace_table_custom_log" "dns_reputation" {
  name              = "DNSReputation_CL"
  workspace_id      = azurerm_log_analytics_workspace.lab-law.id
  plan              = "Analytics"
  retention_in_days = 30

  dynamic "column" {
    for_each = local.dns_reputation_columns
    content {
      name = column.value.name
      type = column.value.type == "datetime" ? "dateTime" : column.value.type
    }
  }
}

resource "azurerm_monitor_data_collection_endpoint" "dns_reputation" {
  name                          = "dce-dns-reputation"
  resource_group_name           = var.rg-lab
  location                      = azurerm_log_analytics_workspace.lab-law.location
  public_network_access_enabled = true
}

resource "azurerm_monitor_data_collection_rule" "dns_reputation" {
  name                        = "dcr-dns-reputation"
  resource_group_name         = var.rg-lab
  location                    = azurerm_log_analytics_workspace.lab-law.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dns_reputation.id

  stream_declaration {
    stream_name = "Custom-DNSReputation"
    dynamic "column" {
      for_each = local.dns_reputation_columns
      content {
        name = column.value.name
        type = column.value.type
      }
    }
  }

  destinations {
    log_analytics {
      name                  = "dns-workspace"
      workspace_resource_id = azurerm_log_analytics_workspace.lab-law.id
    }
  }

  data_flow {
    streams       = ["Custom-DNSReputation"]
    destinations  = ["dns-workspace"]
    transform_kql = "source"
    output_stream = "Custom-DNSReputation_CL"
  }

  depends_on = [azurerm_log_analytics_workspace_table_custom_log.dns_reputation]
}

# Grant dns-rep Monitoring Metrics Publisher on this DCR in portal IAM.
# The deployment identity does not need role-assignment write permission.
output "dns_reputation_ingestion_role_scope" {
  description = "DCR scope for the portal-managed Monitoring Metrics Publisher assignment to dns-rep."
  value       = azurerm_monitor_data_collection_rule.dns_reputation.id
}

resource "azurerm_sentinel_alert_rule_scheduled" "dns_reputation" {
  name                       = "e5507bd4-8ef2-4c81-bbcb-f60da8a704d9"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab-law.id
  display_name               = "DNS domain flagged by VirusTotal"
  description                = "Detects a DNS lookup with malicious or suspicious verdicts in an existing VirusTotal domain report. Investigate reputation freshness and original DNS evidence; this does not prove compromise."
  severity                   = "Medium"
  enabled                    = true
  query_frequency            = "PT5M"
  query_period               = "PT30M"
  trigger_operator           = "GreaterThan"
  trigger_threshold          = 0

  query = <<-KQL
    DNSReputation_CL
    | where TimeGenerated > ago(30m)
    | where ingestion_time() > ago(5m)
    | where MaliciousCount > 0 or SuspiciousCount > 0
    | summarize arg_max(TimeGenerated, *) by Domain, ClientIP, WorkflowRunId
    | extend EventTimeUTC = format_datetime(DNSFirstSeen, "yyyy-MM-dd HH:mm:ss")
    | project TimeGenerated, Domain, ClientIP, MaliciousCount,
              SuspiciousCount, DNSFirstSeen, DNSLastSeen, EventTimeUTC,
              VTAnalysisEpoch, WorkflowRunId
  KQL

  custom_details = {
    Domain          = "Domain"
    ClientIP        = "ClientIP"
    MaliciousCount  = "MaliciousCount"
    SuspiciousCount = "SuspiciousCount"
    DNSFirstSeen    = "DNSFirstSeen"
    DNSLastSeen     = "DNSLastSeen"
    VTAnalysisEpoch = "VTAnalysisEpoch"
    WorkflowRunId   = "WorkflowRunId"
  }

  alert_details_override {
    display_name_format = "DNS reputation flagged: {{Domain}}"
    description_format  = "Client {{ClientIP}} queried {{Domain}} at {{EventTimeUTC}} UTC. Review VirusTotal verdict counts and DNS timestamps in custom details."
  }

  entity_mapping {
    entity_type = "IP"
    field_mapping {
      identifier  = "Address"
      column_name = "ClientIP"
    }
  }

  entity_mapping {
    entity_type = "DNS"
    field_mapping {
      identifier  = "DomainName"
      column_name = "Domain"
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

  depends_on = [
    azurerm_log_analytics_workspace_table_custom_log.dns_reputation,
    azurerm_sentinel_log_analytics_workspace_onboarding.law-sentinal
  ]
}
