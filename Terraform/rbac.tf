resource "azurerm_role_assignment" "DNSLA-LAR" {
  scope = data.azurerm_subscription.current.id
  role_definition_name = "Log Analytics Reader"
  principal_id = data.azurerm_client
}