moved {
  from = azurerm_virtual_network.vnet-lab
  to   = azurerm_virtual_network.vnets["primary"]
}

resource "azurerm_virtual_network" "vnets" {
  for_each            = var.vnet-map
  name                = each.value.name
  location            = each.value.location
  resource_group_name = var.rg-lab
  address_space       = each.value.address_space
}



resource "azurerm_subnet" "subnets" {
  for_each             = var.subnets
  name                 = each.value.name
  resource_group_name  = var.rg-lab
  virtual_network_name = azurerm_virtual_network.vnets[each.value.vnet_key].name
  address_prefixes     = each.value.address_prefixes

}
resource "azurerm_network_interface" "nics" {
  for_each            = var.linux_vms
  name                = "${each.value.name}-nic"
  resource_group_name = var.rg-lab
  location            = azurerm_virtual_network.vnets[var.subnets[each.value.subnet_key].vnet_key].location
  dns_servers         = each.key == "management" ? ["10.60.1.4"] : []


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
  location            = azurerm_virtual_network.vnets[each.value.vnet_key].location
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

resource "azurerm_virtual_network_peering" "vnet01-vnet02-peer" {
  name                         = "vnet-01-vnet02-peering"
  resource_group_name          = var.rg-lab
  virtual_network_name         = azurerm_virtual_network.vnets["primary"].name
  remote_virtual_network_id    = azurerm_virtual_network.vnets["secondary"].id
  allow_virtual_network_access = true
}
resource "azurerm_virtual_network_peering" "vnet02-vnet01-peer" {
  name                         = "vnet-02-vnet01-peering"
  resource_group_name          = var.rg-lab
  virtual_network_name         = azurerm_virtual_network.vnets["secondary"].name
  remote_virtual_network_id    = azurerm_virtual_network.vnets["primary"].id
  allow_virtual_network_access = true
}

resource "azurerm_network_security_rule" "web_management_ssh" {
  name                        = "mgmt-ssh"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "${azurerm_linux_virtual_machine.linux_vms["management"].private_ip_address}/32"
  destination_address_prefix  = azurerm_network_interface.nics["web"].private_ip_address
  network_security_group_name = azurerm_network_security_group.nsgs["web"].name
  resource_group_name         = var.rg-lab
}
resource "azurerm_network_security_rule" "web_management_http" {
  name                        = "mgmt-http"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "${azurerm_linux_virtual_machine.linux_vms["management"].private_ip_address}/32"
  destination_address_prefix  = azurerm_network_interface.nics["web"].private_ip_address
  network_security_group_name = azurerm_network_security_group.nsgs["web"].name
  resource_group_name         = var.rg-lab
}

resource "azurerm_network_security_rule" "Deny_All" {
  name                        = "Deny_All"
  priority                    = 200
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  network_security_group_name = azurerm_network_security_group.nsgs["web"].name
  resource_group_name         = var.rg-lab
}

