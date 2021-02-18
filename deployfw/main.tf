#Deploys a Palo Alto firewall in Azure with a metered SKU
#Sets up a BGP connection based on the configuration of the Aviatrix connection
#Deploy this before creating the connection in the gateway.
#The gateway doesn't allow changing the remote peer address once created
#and the Public IP of the firewall is not yet known.

#$ export AVIATRIX_CONTROLLER_IP = "1.2.3.4"
#$ export AVIATRIX_USERNAME = "admin"
#$ export AVIATRIX_PASSWORD = "password"

terraform {
  required_providers {
    azurerm = {}
  }
}

provider "azurerm" {
  features {}
}

locals {
  subnetbits = (var.subnetsize - (split("/",var.vnetcidr)[1]))
}

#resourcegroups
resource "azurerm_resource_group" "rg" {
  for_each = var.rgnames

  name = each.value
  location = var.region
}

#public IPs
resource "azurerm_public_ip" "pip" {
  for_each = var.publicipnames

  name = each.value.name
  resource_group_name = azurerm_resource_group.rg[each.value.rg].name
  location = var.region
  allocation_method   = "Static"
  sku = "Standard"
}

#network security group
resource "azurerm_network_security_group" "admin_nsg" {
    name = "admin_nsg"
    location = azurerm_resource_group.rg["network"].location
    resource_group_name = azurerm_resource_group.rg["network"].name
}

resource "azurerm_network_security_rule" "admin_rule" {
  name = "admin_access"
  access = "Allow"
  priority = 100
  direction = "Inbound"
  protocol = "*"
  source_port_range = "*"
  destination_port_ranges = ["443","3389"]
  source_address_prefix = var.admin_cidr
  destination_address_prefix = "*"
  resource_group_name = azurerm_resource_group.rg["network"].name
  network_security_group_name = azurerm_network_security_group.admin_nsg.name
}

resource "azurerm_network_security_group" "vpn_nsg" {
  name = "vpn_nsg"
  location = azurerm_resource_group.rg["fw"].location
  resource_group_name = azurerm_resource_group.rg["fw"].name
}

resource "azurerm_network_security_rule" "vpn_rule" {
  name = "vpn_access"
  access = "Allow"
  priority = 100
  direction = "Inbound"
  protocol = "udp"
  source_port_range = "*"
  destination_port_ranges = ["500","4500"]
  source_address_prefix = "0.0.0.0/0"
  destination_address_prefix = "*"
  resource_group_name = azurerm_resource_group.rg["fw"].name
  network_security_group_name = azurerm_network_security_group.vpn_nsg.name
}

#virtual network/subnets
resource "azurerm_virtual_network" "vnet" {
  name = var.vnetname
  location = azurerm_resource_group.rg["network"].location
  resource_group_name = azurerm_resource_group.rg["network"].name
  address_space = [ var.vnetcidr ]
}

resource "azurerm_subnet" "subnet" {
  for_each = var.subnetnames

  name = each.value.name
  resource_group_name = azurerm_virtual_network.vnet.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes = [cidrsubnet(var.vnetcidr,local.subnetbits,each.value.index)]
}

#route table for client
resource "azurerm_route_table" "client_rt" {
  name                = "client_rt"
  location            = azurerm_resource_group.rg["client"].location
  resource_group_name = azurerm_resource_group.rg["client"].name

  route {
    name           = "to-fw_rfc10"
    address_prefix = "10.0.0.0/8"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = cidrhost(azurerm_subnet.subnet["internal"].address_prefixes[0],4)
  }

  route {
    name           = "to-fw_rfc172"
    address_prefix = "172.16.0.0/12"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = cidrhost(azurerm_subnet.subnet["internal"].address_prefixes[0],4)
  }

  route {
    name           = "to-fw_rfc192"
    address_prefix = "192.168.0.0/16"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = cidrhost(azurerm_subnet.subnet["internal"].address_prefixes[0],4)
  }
}

resource "azurerm_subnet_route_table_association" "client_rt_association" {
  subnet_id                 = azurerm_subnet.subnet["client"].id
  route_table_id            = azurerm_route_table.client_rt.id
}

#nics
resource "azurerm_network_interface" "mgmt_nic" {
  name = "${var.subnetnames.mgmt.name}_nic"
  location = azurerm_virtual_network.vnet.location
  resource_group_name = azurerm_resource_group.rg["fw"].name

  ip_configuration {
    name = "ipconfig1"
    subnet_id = azurerm_subnet.subnet["mgmt"].id
    private_ip_address_allocation = "static"
    private_ip_address = cidrhost(azurerm_subnet.subnet["mgmt"].address_prefixes[0],4)
    public_ip_address_id = azurerm_public_ip.pip["mgmt"].id
    primary = true
  }
}

resource "azurerm_network_interface_security_group_association" "mgmt_nsg_association" {
  network_interface_id      = azurerm_network_interface.mgmt_nic.id
  network_security_group_id = azurerm_network_security_group.admin_nsg.id
}

resource "azurerm_network_interface_security_group_association" "mgmt_nsg_association_client" {
  network_interface_id      = azurerm_network_interface.client_nic.id
  network_security_group_id = azurerm_network_security_group.admin_nsg.id
}

resource "azurerm_network_interface" "external_nic" {
  name = "${var.subnetnames.external.name}_nic"
  location = azurerm_virtual_network.vnet.location
  resource_group_name = azurerm_resource_group.rg["fw"].name
  enable_ip_forwarding = true

  ip_configuration {
    name = "ipconfig1"
    subnet_id = azurerm_subnet.subnet["external"].id
    private_ip_address_allocation = "static"
    private_ip_address = cidrhost(azurerm_subnet.subnet["external"].address_prefixes[0],4)
    public_ip_address_id = azurerm_public_ip.pip["external"].id
    primary = true
  }
}

resource "azurerm_network_interface_security_group_association" "external_nsg_association" {
  network_interface_id      = azurerm_network_interface.external_nic.id
  network_security_group_id = azurerm_network_security_group.vpn_nsg.id
}

resource "azurerm_network_interface" "internal_nic" {
  name = "${var.subnetnames.internal.name}_nic"
  location = azurerm_virtual_network.vnet.location
  resource_group_name = azurerm_resource_group.rg["fw"].name
  enable_ip_forwarding = true

  ip_configuration {
    name = "ipconfig1"
    subnet_id = azurerm_subnet.subnet["internal"].id
    private_ip_address_allocation = "static"
    private_ip_address = cidrhost(azurerm_subnet.subnet["internal"].address_prefixes[0],4)
    primary = true
  }
}

resource "azurerm_network_interface" "client_nic" {
  name = "client_nic"
  location = azurerm_virtual_network.vnet.location
  resource_group_name = azurerm_resource_group.rg["client"].name

  ip_configuration {
    name = "ipconfig1"
    subnet_id = azurerm_subnet.subnet["client"].id
    private_ip_address_allocation = "dynamic"
    public_ip_address_id = azurerm_public_ip.pip["client"].id
    primary = true
  }
}

#accept terms
resource "azurerm_marketplace_agreement" "pan_mkt_agreement" {
  plan = "bundle1"
  publisher = "paloaltonetworks"
  offer = "vmseries-flex"  
}

#create VMs
resource "azurerm_linux_virtual_machine" "fw" {
  depends_on = [
    azurerm_marketplace_agreement.pan_mkt_agreement
  ]
  name = var.firewallname
  location = azurerm_resource_group.rg["fw"].location
  resource_group_name = azurerm_resource_group.rg["fw"].name
  size = var.fwsku
  admin_username = var.fw_user
  admin_password = var.FW_PW
  disable_password_authentication = false

  plan {
    name = "bundle1"
    publisher = "paloaltonetworks"
    product = "vmseries-flex"
  }

  source_image_reference {
    publisher = "paloaltonetworks"
    offer     = "vmseries-flex"
    sku       = "bundle1"
    version   = "latest"
  }

  os_disk {
    caching = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface_ids = [azurerm_network_interface.mgmt_nic.id,
                           azurerm_network_interface.external_nic.id,
                           azurerm_network_interface.internal_nic.id
                          ]
  tags = {}
  encryption_at_host_enabled = false
}

resource "azurerm_windows_virtual_machine" "client" {
  name                = "client"
  resource_group_name = azurerm_resource_group.rg["client"].name
  location            = azurerm_resource_group.rg["client"].location
  size                = var.clientsku
  admin_username      = var.client_user
  admin_password      = var.CLIENT_PW
  network_interface_ids = [
    azurerm_network_interface.client_nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  tags = {}
  encryption_at_host_enabled = false
}