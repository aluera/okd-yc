import json
import os
from okd_config import *
import yaml

# Create Dirs
print("---Create Dirs---")
dirs_to_create = "bin", "okd-ignition", "secrets", "temp"
for item in dirs_to_create:
    if os.path.isdir(item) != True:
        os.mkdir(item)
        print(f"Directory  {item} - created!")
    else:
        print(f"Path {item} already exist")
print("---Complete---")


# Generate SSH KEYS
print("---Generate-ssh-keys---")
os.system("sh ./scripts/generate-ssh-key.sh")
print("---Complete---")
# Read Key
with open("./secrets/id_rsa.pub", 'r') as file:
    ssh_key = file.readline().rstrip()

# Modify bastion
print("---Modify bastion.ign---")
with open('./custom-ignition/bastion.ign') as json_file:
    data = json.load(json_file)

data.update(
    {'passwd': {'users': [{'name': 'core', 'sshAuthorizedKeys': [ssh_key]}]}})
with open('./custom-ignition/bastion.ign', 'w') as outfile:
    json.dump(data, outfile)
print("---Complete---")

# Update install Config
print('---Update install config OKD---')
with open("./okd-config/install-config.yaml") as f:
    install_config = yaml.safe_load(f)

install_config.update({"baseDomain": f"{dns_zone}.ru"})
install_config.update({"compute": [
                      {'hyperthreading': 'Enabled', 'name': 'worker', 'replicas': worker_count}]})
install_config.update({'controlPlane': {
                      'hyperthreading': 'Enabled', 'name': 'master', 'replicas': master_count}})
install_config.update({'metadata': {'name': f'{cluster_name}'}})
install_config.update({'sshKey': f'{ssh_key}'})

with open("./okd-config/install-config.yaml", "w") as f:
    yaml.dump(install_config, f)
print("---Complete---")

# Modify Terraform
print("---Modify Terrform scripts---")
os.system(
    f"""sed -i '/token     = "/c\    token     = "'"{yc_token}"'"' ./terraform/main.tf""")
os.system(
    f"""sed -i '/cloud_id  = "/c\    cloud_id  = "'"{yc_cloud_id}"'"' ./terraform/main.tf""")
os.system(
    f"""sed -i '/folder_id = "/c\    folder_id = "'"{yc_folder_id}"'"' ./terraform/main.tf""")

os.system(
    f"""sed -i '/dns_zone_name   = "/c\dns_zone_name   = "'"{dns_zone}.ru."'"' ./terraform/terraform.tfvars""")
os.system(
    f"""sed -i '/cluster_name    = "/c\cluster_name    = "'"{cluster_name}"'"' ./terraform/terraform.tfvars""")
os.system(
    f"""sed -i '/master_count    = /c\master_count    = '"{master_count}"'' ./terraform/terraform.tfvars""")
os.system(
    f"""sed -i '/worker_count    = /c\worker_count    = '"{worker_count}"'' ./terraform/terraform.tfvars""")
print("---Complete---")
# Download OKD
print("---Download OKD---")
os.system("sh ./scripts/download-bin.sh")
print("---Complete---")
# ignition
print("---Generate ignition files---")
os.system("sh ./scripts/generate-okd-ignition.sh")
print("---Complete---")

# Init Terraform
print("---Init Terraform---")
os.system("""sh ./scripts/init-terraform.sh""")
print("---Complete---")
print("Initial Script complete")
