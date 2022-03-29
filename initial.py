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
with open('./custom-ignition/bastion.ign', 'w', encoding='utf8') as outfile:
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
with open("./terraform/terraform.tfvars") as file:
    data_tftvars = file.readlines()

for index, item in enumerate(data_tftvars):
    if item.find("dns_zone_name") != -1:
        data_tftvars[index] = f"""dns_zone_name   = "{dns_zone}.ru."\n"""
    if item.find("cluster_name ") != -1:
        data_tftvars[index] = f"""cluster_name    = "{cluster_name}"\n"""
    if item.find("master_count") != -1:
        data_tftvars[index] = f"""master_count    = {master_count}\n"""
    if item.find("worker_count") != -1:
        data_tftvars[index] = f"""worker_count    = {worker_count}\n"""
    if item.find("bootstrap_count") != -1:
        data_tftvars[index] = f"""bootstrap_count = 1\n"""

with open("./terraform/terraform.tfvars", 'w', encoding='utf8') as file:
    file.writelines(data_tftvars)

with open('./terraform/main.tf') as file:
    data_main_tf = file.readlines()

for index, item in enumerate(data_main_tf):
    if item.find("token") != -1:
        data_main_tf[index] = f'  token     = "{yc_token}"\n'
    if item.find("cloud_id") != -1:
        data_main_tf[index] = f'  cloud_id  = "{yc_cloud_id}"\n'
    if item.find("folder_id") != -1:
        if item.find('"') != -1:
            data_main_tf[index] = f'  folder_id = "{yc_folder_id}"\n'

with open('./terraform/main.tf', 'w', encoding='utf8') as file:
    file.writelines(data_main_tf)
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
