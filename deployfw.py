#Script to deploy PA firewall as client device in Azure
#Needed because Terraform's panos provider fails because the VM doesn't exist yet

import os, subprocess, getpass, json, sys, requests, urllib3, time, json
from ipaddress import IPv4Network,IPv4Address
from colorama import Fore

#requires xmltodict
try:
  import xmltodict
except:
  print(Fore.RED + "Python module xmltodict required for Palo API. Run pip install xmltodict.")
  print(Fore.RESET)
  sys.exit(1)

#requires terraform
try:
  terraform_present = subprocess.run('terraform',stdout=subprocess.DEVNULL)
except:
  print(Fore.RED + "Terraform is required to be installed an in PATH.")
  print(Fore.RESET)
  sys.exit(1)

#disable self-signed warning
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

#check if terraform init is needed
if not os.path.isdir('./deployfw/.terraform'):
  terraform_init = subprocess.run(['terraform','-chdir=deployfw','init'])

if not os.path.isdir('./configurefw/.terraform'):
  terraform_init = subprocess.run(['terraform','-chdir=configurefw','init'])

if not os.path.isdir('./configureaviatrix/.terraform'):
  terraform_init = subprocess.run(['terraform','-chdir=configureaviatrix','init'])

#Load previous terraform tfvars - in JSON because python supports it.
deployfwtfvars = {}
deployfwtfvarsfilename = 'deployfw.tfvars.json'
deployfwtfvarspath = './deployfw/' + deployfwtfvarsfilename
if os.path.isfile(deployfwtfvarspath):
  try:
    deployfwtfvarsfile = open(deployfwtfvarspath,'r')
    deployfwtfvars = json.load(deployfwtfvarsfile)
    deployfwtfvarsfile.close()
  except:
    pass #if this fails, we'll just create a new file

if not deployfwtfvars:
  deployfwtfvars = {
    'fw_user' : 'adminuser',
    'client_user' : 'adminuser',
    'admin_cidr' : '0.0.0.0/0'
  }

fwuser = deployfwtfvars['fw_user']

configurefwtfvarsfilename = 'configurefw.tfvars.json'
configurefwtfvarspath = './configurefw/' + configurefwtfvarsfilename
configurefwtfvars = {}
if os.path.isfile(configurefwtfvarspath):
  try:
    configurefwtfvarsfile = open(configurefwtfvarspath,'r')
    configurefwtfvars = json.load(configurefwtfvarsfile)
    configurefwtfvarsfile.close()
  except:
    pass #if this fails, we'll just create a new file

if not configurefwtfvars:
  configurefwtfvars = {
    'local_asn' : '',
    'remote_asn' : '',
    'controller_pip' : '',
    'controller_admin': 'admin',
    'aviatrix_gateway_name' : '',
    'ext_subnet_cidr': ''
  }

#get controller info
ipvalid = False
while ipvalid == False:
  controller_pip_input = input(Fore.WHITE + "Enter the public IP of the controller [{}]: ".format(configurefwtfvars['controller_pip']))
  if not controller_pip_input:
    controller_pip_input = configurefwtfvars['controller_pip']
  try:
    configurefwtfvars['controller_pip'] = str(IPv4Address(controller_pip_input))
  except:
    print(Fore.YELLOW + '  Please enter a valid IP.')
  else:
    ipvalid = True

controller_admin_input = input(Fore.WHITE + "Please enter the username for the controller [{}]: ".format(configurefwtfvars['controller_admin']))
if controller_admin_input:
  configurefwtfvars['controller_admin'] = controller_admin_input

ctrlpw = "1"
ctrlpw2 = "2"
while ctrlpw != ctrlpw2:
    ctrlpw = getpass.getpass(Fore.WHITE + "Enter a password for the controller user: ")
    ctrlpw2 = getpass.getpass(Fore.WHITE + "Enter it again: ")
    if ctrlpw != ctrlpw2:
      print(Fore.YELLOW + "  Please enter the same password on both lines.")

aviatrix_gateway_name_input = input("Please enter the name of the gateway [{}]: ".format(configurefwtfvars['aviatrix_gateway_name']))
if aviatrix_gateway_name_input:
  configurefwtfvars['aviatrix_gateway_name'] = aviatrix_gateway_name_input

#Firewall password
fwpw = "1"
fwpw2 = "2"
while fwpw != fwpw2:
    fwpw = getpass.getpass(Fore.WHITE + "Enter a password for the firewall/client user adminuser: ")
    fwpw2 = getpass.getpass(Fore.WHITE + "Enter it again: ")
    if fwpw != fwpw2:
      print(Fore.YELLOW + "  Please enter the same password on both lines.")

clientpw = fwpw

# clientpw = "1"
# clientpw2 = "2"
# while clientpw != clientpw2:
#     clientpw = getpass.getpass(Fore.WHITE + "Enter a password for the client user adminuser: ")
#     clientpw2 = getpass.getpass(Fore.WHITE + "Enter it again: ")
#     if fwpw != fwpw2:
#       print(Fore.YELLOW + "  Please enter the same password on both lines.")

#Get management/admin cidr
cidrvalid = False
while cidrvalid == False:
  admincidr_input = input(Fore.WHITE + "Enter your management IP cidr to secure the fw/client interfaces [{}]: ".format(deployfwtfvars['admin_cidr']))
  if not admincidr_input:
    admincidr_input = deployfwtfvars['admin_cidr']
  try:
    deployfwtfvars['admin_cidr'] = str(IPv4Network(admincidr_input))
  except:
    print(Fore.YELLOW + '  Please enter a valid host IP or cidr.')
  else:
    cidrvalid = True

#Get ASNs
asnvalid = False
while asnvalid == False:
  local_asn_input = input(Fore.WHITE + "Enter the local (PAN side) ASN [{}]: ".format(str(configurefwtfvars['local_asn'])))
  if not local_asn_input:
    local_asn_input = str(configurefwtfvars['local_asn'])
  try:
    if int(local_asn_input) > 0 and int(local_asn_input) < 65536:
      configurefwtfvars['local_asn'] = int(local_asn_input)
      asnvalid = True
  except:
    print(Fore.YELLOW + '  Enter a valid asn.')

asnvalid = False
while asnvalid == False:
  remote_asn_input = input(Fore.WHITE + "Enter the remote (gateway side) ASN [{}]: ".format(str(configurefwtfvars['remote_asn'])))
  if not remote_asn_input:
    remote_asn_input = str(configurefwtfvars['remote_asn'])
  try:
    if int(remote_asn_input) > 0 and int(remote_asn_input) < 65536:
      configurefwtfvars['remote_asn'] = int(remote_asn_input)
      asnvalid = True
  except:
    print(Fore.YELLOW + '  Enter a valid asn.')

#write tfvars for deploy
deployfwtfvarsfile = open(deployfwtfvarspath,'w')
json.dump(deployfwtfvars,deployfwtfvarsfile,indent=2)
deployfwtfvarsfile.close()

print(Fore.RESET)
#set up environment for deploy
os.environ['TF_VAR_FW_PW'] = fwpw
os.environ['TF_VAR_CLIENT_PW'] = clientpw

terraform_apply = subprocess.run(['terraform','-chdir=deployfw','apply',"-var-file={}".format(deployfwtfvarsfilename)])
terraform_output = json.loads(subprocess.run(['terraform','-chdir=deployfw','output','-json'], stdout=subprocess.PIPE).stdout.decode('utf-8'))
try:
    pan_mgmt_ip = terraform_output['palo_fw_mgmt_ip']['value']
    pan_vpn_ip = terraform_output['palo_fw_vpn_ip']['value']
    client_ip = terraform_output['client_ip']['value']
    external_subnet_cidr = terraform_output['external_subnet_cidr']['value']
    internal_subnet_cidr = terraform_output['internal_subnet_cidr']['value']
    client_subnet_cidr = terraform_output['client_subnet_cidr']['value']
except:
    print(Fore.RED + "Problem with terraform output. Did it succeed?")
    print(Fore.RESET)
    sys.exit()

#write out tfvars for configure
configurefwtfvars['ext_subnet_cidr'] = external_subnet_cidr
configurefwtfvars['int_subnet_cidr'] = internal_subnet_cidr
configurefwtfvars['client_subnet_cidr'] = client_subnet_cidr
configurefwtfvarsfile = open(configurefwtfvarspath,'w')
json.dump(configurefwtfvars,configurefwtfvarsfile,indent=2)
configurefwtfvarsfile.close()

#Get API for Palo; this also serves the purpose of making sure the device is up before starting the Terraform to config
pan_api_key = ""
while not pan_api_key:
  try:
    response = requests.request("GET","https://{}/api?type=keygen&user={}&password={}".format(pan_mgmt_ip,fwuser,fwpw),verify=False)
    if response.status_code != 200:
      print(Fore.RED + "Getting the PAN API key returned a {}. Try to log in at https://{}.".format(response.status_code,pan_mgmt_ip))
      sys.exit(1)
    pan_api_key = xmltodict.parse(response.text)['response']['result']['key']
  except:
    print(Fore.YELLOW + "Couldn't get PAN API key. Is the device up? Sleeping 10 seconds.")
    time.sleep(10)

print(Fore.RESET)
#set up environment for configure
os.environ['PANOS_HOSTNAME'] = pan_mgmt_ip
os.environ['PANOS_API_KEY'] = pan_api_key
os.environ['PANOS_VERIFY_CERTIFICATE'] = "FALSE"
os.environ['TF_VAR_CONTROLLER_PW'] = ctrlpw

terraform_apply = subprocess.run(['terraform','-chdir=configurefw','apply',"-var-file={}".format(configurefwtfvarsfilename)])
terraform_output = json.loads(subprocess.run(['terraform','-chdir=configurefw','output','-json'], stdout=subprocess.PIPE).stdout.decode('utf-8'))

#commit
commit_status = False
while commit_status == False:
  try:
    commit = requests.request("GET","https://{}/api?key={}&type=commit&cmd=<commit></commit>".format(pan_mgmt_ip,pan_api_key),verify=False)
    if commit.status_code == 200:
      print(commit.text)
      commit_status = True
      print(Fore.WHITE + "Commit succeeded.")
    else:
      print(Fore.RED + "Commit returned a {}. Try to log in at https://{} and commit manually.".format(commit.status_code,pan_mgmt_ip))
  except:
    print(Fore.YELLOW + "Commit errored out, trying again in 10 seconds.")
    time.sleep(10)

try:
  psk = terraform_output['psk']['value']
  tunnel_cidr = terraform_output['tunnel_cidr']['value']
except:
  print(Fore.RED + "Error getting the PSK, cannot configure the Aviatrix gateway.")
  print(Fore.RESET)
  sys.exit(1)


print("Configuring controller.")

#Configure controller
configureaviatrixtfvars = {
  'controller_pip' : configurefwtfvars['controller_pip'],
  'controller_admin': configurefwtfvars['controller_admin'],
  'aviatrix_gateway_name': configurefwtfvars['aviatrix_gateway_name'],
  #flipped on purpose - local/remote is from the PAN perspective
  'local_asn' : configurefwtfvars['remote_asn'],
  'remote_asn' : configurefwtfvars['local_asn'],
  'tunnel_cidr' : tunnel_cidr,
  'psk' : psk,
  'pan_vpn_ip' : pan_vpn_ip
}

configureaviatrixtfvarsfilename = 'configureaviatrix.tfvars.json'
configureaviatrixtfvarspath = './configureaviatrix/' + configureaviatrixtfvarsfilename
configureaviatrixtfvarsfile = open(configureaviatrixtfvarspath,'w')
json.dump(configureaviatrixtfvars,configureaviatrixtfvarsfile,indent=2)
configureaviatrixtfvarsfile.close()

terraform_apply = subprocess.run(['terraform','-chdir=configureaviatrix','apply',"-var-file={}".format(configureaviatrixtfvarsfilename)])

print(Fore.WHITE + "FW Mgmt IP: {}".format(pan_mgmt_ip))
print(Fore.WHITE + "Client IP: {}".format(client_ip))