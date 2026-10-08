resource "azurerm_role_assignment" "DNSLA-LAR" {
  scope = data.azurerm_subscription.current.id
  role_definition_name = "Log Analytics Reader"
  principal_id = azurerm_logic_app_workflow.dns_rep.identity[0].principal_id
}