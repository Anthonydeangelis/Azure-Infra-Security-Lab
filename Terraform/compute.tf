resource "azurerm_linux_virtual_machine" "linux_vms" {
  for_each            = var.linux_vms
  name                = each.value.name
  location            = azurerm_virtual_network.vnets[var.subnets[each.value.subnet_key].vnet_key].location
  resource_group_name = var.rg-lab
  size                = each.value.size
  admin_username      = var.admin_username
  identity {
    type = "SystemAssigned"
  }

  network_interface_ids = [
  azurerm_network_interface.nics[each.key].id]

  disable_password_authentication = true


  admin_ssh_key {
    username   = var.admin_username
    public_key = var.public_key
  }
  os_disk {
    name                 = "${each.key}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = each.value.storage_account_type
    disk_size_gb         = each.value.disk_size_gb
  }
  source_image_reference {
    publisher = var.image.publisher
    offer     = var.image.offer
    sku       = var.image.sku
    version   = var.image.version
  }

}

resource "azurerm_virtual_machine_extension" "ama" {
  for_each = {
    for key, vm in var.linux_vms :
    key => vm
    if contains(["management", "web", "test"], key)
  }

  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.linux_vms[each.key].id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
}

resource "azurerm_managed_disk" "database_data" {
  name                 = "disk-lab-db-data"
  location             = var.location
  resource_group_name  = var.rg-lab
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.db-disk
}

resource "azurerm_virtual_machine_data_disk_attachment" "database_data" {
  managed_disk_id    = azurerm_managed_disk.database_data.id
  virtual_machine_id = azurerm_linux_virtual_machine.linux_vms["database"].id
  lun                = 0
  caching            = "None"
}
