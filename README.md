# palo-aviatrix-vpn
Spins up a metered Palo Alto in Azure and connects to an Aviatrix HA transit gateway.
Also spins up a Windows VM to simulate an on-prem client.
For lab/repro purposes.

# Credentials
* The username is adminuser for both firewall management and the client VM.
* The password is shared between firewall management and the client VM.

# Issues
* The terraform code expects Aviatrix HA Transit Gateway deployment. It'll complain otherwise.

# Requirements
* Azure subscription
* Azure CLI installed
* python3
* xmltodict module
* terraform in PATH
* deployed Aviatrix contoller with admin credentials (www.aviatrix.com)

# Run it
python deployfw.pw

There are a series of questions, including the controller password. Once you answer the questions, 3 terraform deployments are kicked off.
* deployfw
* configurefw
* configureaviatrix

# Why not all in Terraform
Terraform providers can't use depends_on. The public IP of the firewall
The Panos provider can't commit changes, need to use the GUI/CLI/API.
