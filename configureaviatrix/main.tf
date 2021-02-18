terraform {
  required_providers {
    aviatrix = {
      source = "aviatrixsystems/aviatrix"
    }
  }
}

#$ export AVIATRIX_CONTROLLER_IP = "1.2.3.4"
#$ export AVIATRIX_USERNAME = "admin"
#$ export AVIATRIX_PASSWORD = "password"

provider "aviatrix" {
  controller_ip = var.controller_pip
  username = var.controller_admin
  password = var.CONTROLLER_PW #environment variable
}

data "aviatrix_gateway" "gw" {
  gw_name = var.aviatrix_gateway_name
}

resource "aviatrix_transit_external_device_conn" "ex-conn" {
  vpc_id            = data.aviatrix_gateway.gw.vpc_id
  connection_name   = "my_connection"
  gw_name           = data.aviatrix_gateway.gw.gw_name
  connection_type   = "bgp"
  tunnel_protocol   = "IPsec"
  bgp_local_as_num  = var.local_asn
  bgp_remote_as_num = var.remote_asn
  local_tunnel_cidr = "${cidrhost(var.tunnel_cidr[0],2)}/30,${cidrhost(var.tunnel_cidr[1],2)}/30"
  remote_tunnel_cidr = "${cidrhost(var.tunnel_cidr[0],1)}/30,${cidrhost(var.tunnel_cidr[1],1)}/30"
  remote_gateway_ip = var.pan_vpn_ip
  pre_shared_key = var.psk
}