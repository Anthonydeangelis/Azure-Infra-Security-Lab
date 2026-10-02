resource "azurerm_resource_group" "labrg" {
  name = var.rg-lab
  location = var.location
}
resource "azurerm_resource_group" "sarg" {
  name = var.rg-sa
  location = var.location
  }
resource "azurerm_storage_account" "sa-tfstate" {
  name                     = var.sa-tfstate
  resource_group_name      = azurerm_resource_group.sarg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind = "StorageV2"

  network_rules {
    default_action = "Deny"
    ip_rules = [var.macip] 
  }

  }
resource "azurerm_storage_container" "sa-tfstate-container" {
  name = var.container-tfstate
  storage_account_id = azurerm_storage_account.sa-tfstate.id
  container_access_type = "private"
}

data "azurerm_client_config" "current" {
}
  
resource "azurerm_role_assignment" "sa-role-acess" {
  scope = azurerm_storage_container.sa-tfstate-container.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id = data.azurerm_client_config.current.object_id
}