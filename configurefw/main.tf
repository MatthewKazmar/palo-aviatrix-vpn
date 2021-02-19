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
    panos = {
      source = "paloaltonetworks/panos"
    }
    aviatrix = {
      source = "aviatrixsystems/aviatrix"
    }
  }
}

provider "aviatrix" {
  controller_ip = var.controller_pip
  username = var.controller_admin
  password = var.CONTROLLER_PW #environment variable
}

data "aviatrix_gateway" "gw" {
  gw_name = var.aviatrix_gateway_name
}

provider "panos" {}

#configure Palo interfaces
resource "panos_ethernet_interface" "external_nic" {
  name = "ethernet1/1"
  vsys = "vsys1"
  mode = "layer3"
  enable_dhcp = true
}

resource "panos_ethernet_interface" "internal_nic" {
  name = "ethernet1/2"
  vsys = "vsys1"
  mode = "layer3"
  enable_dhcp = true
}

resource "panos_tunnel_interface" "tunnel_1" {
    name = "tunnel.1"
    static_ips = ["${cidrhost(var.tunnel_cidr[0],1)}/30"]
    mtu = 1436
}

resource "panos_tunnel_interface" "tunnel_2" {
    name = "tunnel.2"
    static_ips = ["${cidrhost(var.tunnel_cidr[1],1)}/30"]
    mtu = 1436
}

#sec zones
resource "panos_zone" "external_zone" {
  name = "external"
  mode = "layer3"
  interfaces = [
    panos_ethernet_interface.external_nic.name
  ]
}

resource "panos_zone" "internal_zone" {
  name = "internal"
  mode = "layer3"
  interfaces = [
    panos_ethernet_interface.internal_nic.name
  ]
}

resource "panos_zone" "cloud_zone" {
  name = "cloud"
  mode = "layer3"
  interfaces = [
    panos_tunnel_interface.tunnel_1.name,
    panos_tunnel_interface.tunnel_2.name
  ]
}

#virtual router
resource "panos_virtual_router" "default_vr" {
  name = "default"
  interfaces = [
      panos_ethernet_interface.external_nic.name,
      panos_ethernet_interface.internal_nic.name,
      panos_tunnel_interface.tunnel_1.name,
      panos_tunnel_interface.tunnel_2.name
  ]
}

resource "panos_static_route_ipv4" "default_route" {
  name = "default_route"
  virtual_router = panos_virtual_router.default_vr.name
  destination = "0.0.0.0/0"
  interface = "ethernet1/1"
  next_hop = cidrhost(var.ext_subnet_cidr,1)
}

resource "panos_static_route_ipv4" "client_subnet" {
  name = "client_subnet"
  virtual_router = panos_virtual_router.default_vr.name
  destination = var.client_subnet_cidr
  interface = "ethernet1/2"
  next_hop = cidrhost(var.int_subnet_cidr,1)
}

#NAT rule
resource "panos_nat_rule_group" "natgroup" {
  rule {
      name = "to-Internet"
      original_packet {
          source_zones = [panos_zone.internal_zone.name]
          destination_zone = panos_zone.external_zone.name
          destination_interface = panos_ethernet_interface.external_nic.name
          source_addresses = ["any"]
          destination_addresses = ["any"]
      }
      translated_packet {
          source {
            dynamic_ip_and_port {
              interface_address {
                interface = panos_ethernet_interface.external_nic.name
              }
            }
          }
          destination {}
      }
  }
}

#initial policy rules
resource "panos_security_rule_group" "default_policy" {
  rule {
    name = "to-internet"
    source_zones = [panos_zone.internal_zone.name]
    source_addresses = ["any"]
    source_users = ["any"]
    hip_profiles = ["any"]
    destination_zones = [panos_zone.external_zone.name]
    destination_addresses = ["any"]
    applications = ["any"]
    services = ["any"]
    categories = ["any"]
    action = "allow"
  }
  rule {
    name = "allow-internal"
    source_zones = [panos_zone.internal_zone.name,panos_zone.cloud_zone.name]
    source_addresses = ["any"]
    source_users = ["any"]
    hip_profiles = ["any"]
    destination_zones = [panos_zone.internal_zone.name,panos_zone.cloud_zone.name]
    destination_addresses = ["any"]
    applications = ["any"]
    services = ["any"]
    categories = ["any"]
    action = "allow"
  }
  rule {
    name = "allow-vpn"
    source_zones = [panos_zone.external_zone.name]
    source_addresses = ["any"]
    source_users = ["any"]
    hip_profiles = ["any"]
    destination_zones = [panos_zone.external_zone.name]
    destination_addresses = ["any"]
    applications = ["ipsec"]
    services = ["any"]
    categories = ["any"]
    action = "allow"
  }
  rule {
    name = "deny-all-log"
    source_zones = ["any"]
    source_addresses = ["any"]
    source_users = ["any"]
    hip_profiles = ["any"]
    destination_zones = ["any"]
    destination_addresses = ["any"]
    applications = ["any"]
    services = ["any"]
    categories = ["any"]
    action = "deny"
  }
}

#create ike/ipsec profiles
resource "panos_ike_crypto_profile" "aviatrix_ike" {
    name = "aviatrix_ike"
    dh_groups = ["group14"]
    authentications = ["sha256"]
    encryptions = ["aes-256-cbc"]
    lifetime_type = "seconds"
    lifetime_value = 28800
}

resource "panos_ipsec_crypto_profile" "aviatrix_ipsec" {
    name = "aviatrix_ipsec"
    authentications = ["sha256"]
    encryptions = ["aes-256-cbc"]
    dh_group = "group14"
    lifetime_type = "seconds"
    lifetime_value = 28800
}

#generate psk
resource "random_string" "psk" {
  length = 31
  special = false
}

#create ike gateways
resource "panos_ike_gateway" "gateway_1" {
  name = "gateway_1"
  peer_ip_type = "ip"
  peer_ip_value = data.aviatrix_gateway.gw.public_ip
  interface = "ethernet1/1"
  pre_shared_key = random_string.psk.result
  peer_id_type = "ipaddr"
  peer_id_value = data.aviatrix_gateway.gw.public_ip
  ikev1_crypto_profile = "aviatrix_ike"
  enable_nat_traversal = true
  nat_traversal_keep_alive = 60
  enable_dead_peer_detection = true
  enable_liveness_check = true
  depends_on = [ 
    panos_ethernet_interface.external_nic
  ]
}

resource "panos_ike_gateway" "gateway_2" {
  name = "gateway_2"
  peer_ip_type = "ip"
  peer_ip_value = data.aviatrix_gateway.gw.peering_ha_public_ip
  interface = "ethernet1/1"
  pre_shared_key = random_string.psk.result
  peer_id_type = "ipaddr"
  peer_id_value = data.aviatrix_gateway.gw.peering_ha_public_ip
  ikev1_crypto_profile = "aviatrix_ike"
  enable_nat_traversal = true
  nat_traversal_keep_alive = 60
  enable_dead_peer_detection = true
  enable_liveness_check = true
  depends_on = [ 
    panos_ethernet_interface.external_nic
  ]
}

#create ipsec tunnels
resource "panos_ipsec_tunnel" "ipsec_1" {
  name = "ipsec_1"
  tunnel_interface = "tunnel.1"
  anti_replay = true
  ak_ike_gateway = "gateway_1"
  ak_ipsec_crypto_profile = "aviatrix_ipsec"
  depends_on = [ 
    panos_tunnel_interface.tunnel_1,
    panos_ike_gateway.gateway_1
  ]
}

resource "panos_ipsec_tunnel" "ipsec_2" {
  name = "ipsec_2"
  tunnel_interface = "tunnel.2"
  anti_replay = true
  ak_ike_gateway = "gateway_2"
  ak_ipsec_crypto_profile = "aviatrix_ipsec"
  depends_on = [ 
    panos_tunnel_interface.tunnel_2,
    panos_ike_gateway.gateway_2
  ]
}

#configure bgp
resource "panos_bgp" "bgp" {
    virtual_router = panos_virtual_router.default_vr.name
    router_id = cidrhost(var.ext_subnet_cidr,4)
    as_number = var.local_asn
    install_route = true
}

resource "panos_bgp_peer_group" "bgp_pg" {
    virtual_router = panos_bgp.bgp.virtual_router
    name = "aviatrix_gateways"
}

resource "panos_bgp_peer" "bgp_peer_1" {
  virtual_router = panos_bgp.bgp.virtual_router
  bgp_peer_group = panos_bgp_peer_group.bgp_pg.name
  name = "gateway_1"
  peer_as = var.remote_asn
  local_address_interface = panos_tunnel_interface.tunnel_1.name
  local_address_ip = "${cidrhost(var.tunnel_cidr[0],1)}/30"
  peer_address_ip = cidrhost(var.tunnel_cidr[0],2)
  address_family_type = "ipv4"
}

resource "panos_bgp_peer" "bgp_peer_2" {
  virtual_router = panos_bgp.bgp.virtual_router
  bgp_peer_group = panos_bgp_peer_group.bgp_pg.name
  name = "gateway_2"
  peer_as = var.remote_asn
  local_address_interface = panos_tunnel_interface.tunnel_2.name
  local_address_ip = "${cidrhost(var.tunnel_cidr[1],1)}/30"
  peer_address_ip = cidrhost(var.tunnel_cidr[1],2)
  address_family_type = "ipv4"
}

resource "panos_redistribution_profile_ipv4" "redist_connect" {
    virtual_router = panos_virtual_router.default_vr.name
    name = "redist-connect"
    priority = 1
    action = "redist"
    types = ["connect"]
}

resource "panos_redistribution_profile_ipv4" "redist_static" {
    virtual_router = panos_virtual_router.default_vr.name
    name = "redist-static"
    priority = 2
    action = "redist"
    types = ["static"]
    interfaces = [ "ethernet1/2" ]
}

resource "panos_bgp_redist_rule" "redist-rule_connect" {
    virtual_router = panos_virtual_router.default_vr.name
    route_table = "unicast"
    name = panos_redistribution_profile_ipv4.redist_connect.name
}

resource "panos_bgp_redist_rule" "redist-rule-connect" {
    virtual_router = panos_virtual_router.default_vr.name
    route_table = "unicast"
    name = panos_redistribution_profile_ipv4.redist_static.name
}