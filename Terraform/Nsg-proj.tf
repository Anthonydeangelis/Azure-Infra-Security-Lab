variable "nsg_workflow_name" {
  description = "Existing Logic App name."
  type        = string
  default     = "NSG-change"
}

variable "nsg_sentinel_connection_name" {
  description = "Existing Sentinel API connection in the same resource group and region."
  type        = string
  default     = "azuresentinel-1"
}

variable "nsg_automation_order" {
  description = "Order among alert-created automation rules."
  type        = number
  default     = 100
}

# Deploy the Logic App definition through ARM using the AzureRM provider.
resource "azurerm_resource_group_template_deployment" "nsg_change_workflow" {
  name                = "nsg-change-workflow"
  resource_group_name = var.rg-lab
  deployment_mode     = "Incremental"

  parameters_content = jsonencode({
    workflowName = {
      value = var.nsg_workflow_name
    }
    location = {
      value = var.location
    }
    sentinelConnectionName = {
      value = var.nsg_sentinel_connection_name
    }
  })

  template_content = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"

    parameters = {
      workflowName = {
        type = "string"
      }
      location = {
        type = "string"
      }
      sentinelConnectionName = {
        type = "string"
      }
    }

    resources = [
      {
        type       = "Microsoft.Logic/workflows"
        apiVersion = "2019-05-01"
        name       = "[parameters('workflowName')]"
        location   = "[parameters('location')]"

        identity = {
          type = "SystemAssigned"
        }

        properties = {
          state = "Enabled"

          definition = {
            "$schema"      = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
            contentVersion = "1.0.0.0"

            parameters = {
              "$connections" = {
                type         = "Object"
                defaultValue = {}
              }
            }

            triggers = {
              Microsoft_Sentinel_alert = {
                type = "ApiConnectionWebhook"

                inputs = {
                  host = {
                    connection = {
                      name = "@parameters('$connections')['sentinel']['connectionId']"
                    }
                  }

                  body = {
                    callback_url = "@listCallbackUrl()"
                  }

                  path = "/subscribe"
                }
              }
            }

            actions = {}
            outputs = {}
          }

          parameters = {
            "$connections" = {
              value = {
                sentinel = {
                  id = "[subscriptionResourceId('Microsoft.Web/locations/managedApis', parameters('location'), 'azuresentinel')]"

                  connectionId = "[resourceId('Microsoft.Web/connections', parameters('sentinelConnectionName'))]"

                  connectionName = "[parameters('sentinelConnectionName')]"

                  connectionProperties = {
                    authentication = {
                      type = "ManagedServiceIdentity"
                    }
                  }
                }
              }
            }
          }
        }
      }
    ]

    outputs = {
      workflowId = {
        type  = "string"
        value = "[resourceId('Microsoft.Logic/workflows', parameters('workflowName'))]"
      }

      principalId = {
        type = "string"

        value = "[reference(resourceId('Microsoft.Logic/workflows', parameters('workflowName')), '2019-05-01', 'Full').identity.principalId]"
      }
    }
  })
}

# Route alerts from the NSG analytics rule to the Logic App.
resource "azurerm_sentinel_automation_rule" "nsg_change_to_playbook" {
  name = uuidv5(
    "url",
    "${lower(azurerm_log_analytics_workspace.lab-law.id)}/automation/nsg-change-to-playbook"
  )

  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab-law.id
  display_name               = "Run NSG checker on NSG change alerts"
  order                      = var.nsg_automation_order
  enabled                    = true

  triggers_on   = "Alerts"
  triggers_when = "Created"

  condition_json = jsonencode([
    {
      conditionType = "Property"

      conditionProperties = {
        propertyName = "AlertAnalyticRuleIds"
        operator     = "Contains"

        propertyValues = [
          azurerm_sentinel_alert_rule_scheduled.nsg-config.id
        ]
      }
    }
  ])

  action_playbook {
    order = 1

    logic_app_id = jsondecode(
      azurerm_resource_group_template_deployment.nsg_change_workflow.output_content
    ).workflowId.value
  }
}

resource "azurerm_storage_account" "nsg_functions" {
  name                     = "antsansgfunction01"
  resource_group_name      = var.rg-lab
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled = false
}

resource "azurerm_storage_container" "nsg_deployment" {
  name                  = "function-deployments"
  storage_account_id    = azurerm_storage_account.nsg_functions.id
  container_access_type = "private"
}

resource "azurerm_user_assigned_identity" "nsg_functions" {
  name                = "mi-nsg-functions"
  resource_group_name = var.rg-lab
  location            = var.location
}

resource "azurerm_service_plan" "nsg_functions" {
  name                = "plan-nsg-functions"
  resource_group_name = var.rg-lab
  location            = var.location

  os_type  = "Linux"
  sku_name = "FC1"
}

resource "azurerm_function_app_flex_consumption" "nsg_fa" {
  name                = "ant-nsg-checker-01"
  resource_group_name = var.rg-lab
  location            = var.location
  service_plan_id     = azurerm_service_plan.nsg_functions.id

runtime_name    = "python"
runtime_version = "3.14"

storage_container_type = "blobContainer"

storage_container_endpoint = "${azurerm_storage_account.nsg_functions.primary_blob_endpoint}${azurerm_storage_container.nsg_deployment.name}"

storage_authentication_type        = "UserAssignedIdentity"
storage_user_assigned_identity_id = azurerm_user_assigned_identity.nsg_functions.id

https_only = true

identity {
  type         = "UserAssigned"
  identity_ids = [azurerm_user_assigned_identity.nsg_functions.id]
}

app_settings = {
  AzureWebJobsStorage__accountName = azurerm_storage_account.nsg_functions.name
  AzureWebJobsStorage__credential  = "managedidentity"
  AzureWebJobsStorage__clientId    = azurerm_user_assigned_identity.nsg_functions.client_id
}

site_config {}
}