variable admin_cidr { type = string }
variable fw_user { default = "adminuser" }
variable client_user { default = "adminuser" }
variable FW_PW { type = string }
variable CLIENT_PW { type = string }

variable region { default = "northcentralus "}

variable rgnames { 
  default = {
    network = "network_rg"
    fw = "firewall_rg"
    client = "client_rg"
  }
}

variable firewallname { default = "panfwvm" }

variable fwsku { default = "Standard_B2ms" } #Palo needs mgmt, external, internal - b2ms allows 3 NICs
variable clientsku { default = "Standard_B2s" } #2 core, 4gb

variable vnetname { default = "pan_vnet"}
variable vnetcidr { default = "172.31.64.0/22" }
variable subnetsize { default = "27" }
variable subnetnames {
  default = {
    mgmt = {
      index = 0
      name = "pan_mgmt"
    }
    external = {
      index = 1
      name = "pan_external"
    }
    internal = {
      index = 2
      name = "pan_internal"
    }
    client = {
      index = 3
      name = "client"
    }
  }
}

variable publicipnames {
  default = {
    mgmt = {
      name = "pan_mgmt_pip"
      rg = "fw"
    }
    external = {
      name = "pan_external_pip"
      rg = "fw"
    }
    client = {
      name = "client_pip"
      rg = "client"
    }
  }
}