resource "azurerm_virtual_network" "vnet-lab" {
  name                = var.vnet_name
  location            = var.location
  resource_group_name = var.rg-lab
  address_space       = var.vnet_address_space
}

resource "azurerm_virtual_network" "vnet-lab02" {
  name = "vnet-lab02"
  location = " eastus"
  resource_group_name = var.rg-lab
  address_space = "10.60.0.0/16"
}
resource "azurerm_subnet" "subnets" {
  for_each             = var.subnets
  name                 = each.value.name
  resource_group_name  = azurerm_virtual_network.vnet-lab.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet-lab.name
  address_prefixes     = each.value.address_prefixes

}
resource "azurerm_network_interface" "nics" {
  for_each            = var.linux_vms
  name                = "${each.value.name}-nic"
  resource_group_name = azurerm_virtual_network.vnet-lab.resource_group_name
  location            = var.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnets[each.value.subnet_key].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = each.key == "management" ? azurerm_public_ip.mgmt_pip.id : null
  }
}

resource "azurerm_public_ip" "mgmt_pip" {
  name                = "pip-lab-mgmt"
  location            = var.location
  resource_group_name = var.rg-lab
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "nsgs" {
  for_each = var.subnets

  name                = "nsg-${each.key}"
  location            = var.location
  resource_group_name = var.rg-lab
}

resource "azurerm_subnet_network_security_group_association" "subnets" {
  for_each                  = var.subnets
  subnet_id                 = azurerm_subnet.subnets[each.key].id
  network_security_group_id = azurerm_network_security_group.nsgs[each.key].id

}

resource "azurerm_network_security_rule" "management_ssh" {
  name                        = "Allow-SSH-From-Mac"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "${var.macip}/32"
  destination_address_prefix  = "*"
  resource_group_name         = var.rg-lab
  network_security_group_name = azurerm_network_security_group.nsgs["management"].name
}

