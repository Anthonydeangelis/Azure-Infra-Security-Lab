terraform {
  backend "azurerm" {
    storage_account_name = "saanttfstate01"
    container_name       = "tfstate"
    key                  = "azure-lab.tfstate"
    use_azuread_auth     = true
  }
}
