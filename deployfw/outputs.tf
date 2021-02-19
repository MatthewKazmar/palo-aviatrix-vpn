output "palo_fw_mgmt_ip" {
  value = azurerm_public_ip.pip["mgmt"].ip_address
}

output "palo_fw_vpn_ip" {
  value = azurerm_public_ip.pip["external"].ip_address
}

output "client_ip" {
  value = azurerm_public_ip.pip["client"].ip_address
}

output "external_subnet_cidr" {
  value = azurerm_subnet.subnet["external"].address_prefixes[0]
}

output "internal_subnet_cidr" {
  value = azurerm_subnet.subnet["internal"].address_prefixes[0]
}

output "client_subnet_cidr" {
  value = azurerm_subnet.subnet["client"].address_prefixes[0]
}