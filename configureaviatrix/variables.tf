variable controller_pip { type = string }
variable controller_admin { type = string }
variable CONTROLLER_PW { 
  type = string
  sensitive = true
}
variable aviatrix_gateway_name { type = string }
variable local_asn { type = number }
variable remote_asn { type = number }
variable tunnel_cidr { type = list } #2 /30 ranges as configured on the gateway
variable pan_vpn_ip { type = string }
variable psk { type = string }