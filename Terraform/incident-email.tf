# AzureRM 5.0.0 does not expose parameterValueType on azurerm_api_connection.
# Deploy this managed-identity connection through ARM while retaining Terraform ownership.
data "azurerm_managed_api" "sentinel" {
  name     = "azuresentinel"
  location = var.location
}

resource "azurerm_resource_group_template_deployment" "sentinel_email_connection" {
  name                = "sentinel-email-connection"
  resource_group_name = var.rg-lab
  deployment_mode     = "Incremental"

  template_content = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"

    resources = [{
      type       = "Microsoft.Web/connections"
      apiVersion = "2016-06-01"
      name       = "incident-email-sentinel"
      location   = var.location
      kind       = "V1"
      properties = {
        displayName        = "Sentinel incident email"
        parameterValueType = "Alternative"
        api = {
          id = data.azurerm_managed_api.sentinel.id
        }
      }
    }]

    outputs = {
      connectionId = {
        type  = "string"
        value = "[resourceId('Microsoft.Web/connections', 'incident-email-sentinel')]"
      }
    }
  })
}

# Sentinel invokes this webhook through an automation rule or manual playbook run.
# It does not poll for incidents and does not run on the DNS workflow's schedule.
resource "azurerm_logic_app_trigger_custom" "sentinel_incident" {
  name         = "Microsoft_Sentinel_incident"
  logic_app_id = azurerm_logic_app_workflow.incident_email.id

  body = jsonencode({
    type = "ApiConnectionWebhook"
    inputs = {
      body = {
        callback_url = "@{listCallbackUrl()}"
      }
      host = {
        connection = {
          name = "@parameters('$connections')['azuresentinel']['connectionId']"
        }
      }
      path = "/incident-creation"
    }
  })
}

variable "incident_email_recipient" {
  description = "Single destination mailbox for Sentinel incident notifications. Set in private tfvars and the CI TERRAFORM_TFVARS secret."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s;]+@[^@\\s;]+\\.[^@\\s;]+$", var.incident_email_recipient))
    error_message = "Provide one recipient email address."
  }
}

# Format incident fields into a reusable notification for DNS, SSH, or NSG incidents.
resource "azurerm_logic_app_action_custom" "incident_email_details" {
  name         = "Incident_Email_Details"
  logic_app_id = azurerm_logic_app_workflow.incident_email.id

  body = jsonencode({
    type     = "Table"
    runAfter = {}
    inputs = {
      format = "HTML"
      from = [
        { Field = "Incident number", Value = "@string(triggerBody()?['object']?['properties']?['incidentNumber'])" },
        { Field = "Title", Value = "@coalesce(triggerBody()?['object']?['properties']?['title'], 'Sentinel incident')" },
        { Field = "Severity", Value = "@coalesce(triggerBody()?['object']?['properties']?['severity'], 'Unknown')" },
        { Field = "Status", Value = "@coalesce(triggerBody()?['object']?['properties']?['status'], 'Unknown')" },
        { Field = "Description", Value = "@coalesce(triggerBody()?['object']?['properties']?['description'], 'See incident for investigation details.')" },
        { Field = "First activity (UTC)", Value = "@coalesce(triggerBody()?['object']?['properties']?['firstActivityTimeUtc'], 'Not supplied')" },
        { Field = "Last activity (UTC)", Value = "@coalesce(triggerBody()?['object']?['properties']?['lastActivityTimeUtc'], 'Not supplied')" },
        { Field = "Incident link", Value = "@coalesce(triggerBody()?['object']?['properties']?['incidentUrl'], 'Open Microsoft Defender to investigate.')" }
      ]
    }
  })

  depends_on = [azurerm_logic_app_trigger_custom.sentinel_incident]
}

resource "azurerm_logic_app_action_custom" "send_incident_email" {
  name         = "Send_Incident_Email"
  logic_app_id = azurerm_logic_app_workflow.incident_email.id

  body = jsonencode({
    type = "ApiConnection"
    runAfter = {
      Incident_Email_Details = ["Succeeded"]
    }
    inputs = {
      host = {
        connection = {
          name = "@parameters('$connections')['outlook']['connectionId']"
        }
      }
      method = "post"
      path   = "/v2/Mail"
      body = {
        To         = var.incident_email_recipient
        Subject    = "[Sentinel] @{triggerBody()?['object']?['properties']?['severity']} - @{triggerBody()?['object']?['properties']?['title']}"
        Body       = "@body('Incident_Email_Details')"
        Importance = "Normal"
      }
      # Avoid automatically sending duplicates after ambiguous mail API timeouts.
      # Failed sends must be reviewed in playbook run history before manual retry.
      retryPolicy = { type = "none" }
    }
  })

  depends_on = [azurerm_logic_app_action_custom.incident_email_details]
}

# Notify for newly created incidents linked to the DNS, SSH, or NSG lab rules.
# Sentinel's service identity needs Automation Contributor on the playbook RG
# (managed in portal IAM); the playbook identity separately needs Sentinel Reader.
resource "azurerm_sentinel_automation_rule" "dns_incident_email" {
  name                       = "527c93ee-ae45-43af-b7ec-b014ff09b8ad"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab-law.id
  display_name               = "Email new sec incidents"
  order                      = 100
  enabled                    = true
  triggers_on                = "Incidents"
  triggers_when              = "Created"

  condition_json = jsonencode([{
    conditionType = "Property"
    conditionProperties = {
      propertyName   = "IncidentRelatedAnalyticRuleIds"
      operator       = "Contains"
      propertyValues = [azurerm_sentinel_alert_rule_scheduled.dns_reputation.id, azurerm_sentinel_alert_rule_scheduled.ssh_failures.id, azurerm_sentinel_alert_rule_scheduled.nsg-config.id]
    }
  }])

  action_playbook {
    order        = 1
    logic_app_id = azurerm_logic_app_workflow.incident_email.id
  }

  depends_on = [azurerm_logic_app_action_custom.send_incident_email]
}
