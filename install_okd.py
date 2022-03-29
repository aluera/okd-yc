#### Install OKD ####
import subprocess
import os
import re
import time
from okd_config import cluster_name, dns_zone


def tf_destroy():
    terraform_destroy = subprocess.run(
        ["terraform destroy -auto-approve"], shell=True, stderr=subprocess.PIPE, stdout=subprocess.PIPE)
    if terraform_destroy.returncode != 0:
        print(terraform_destroy.stderr.decode('utf8'))
        exit("Something went wrong in apply!")
    else:
        print(terraform_destroy.stdout.decode('utf8'))
        exit("Terraform destroy comple, but install not complete, try again!")


if 'initial.py' not in os.listdir():
    exit("This is not the right directory")

os.chdir("terraform")

if 'main.tf' not in os.listdir():
    exit("This is not a Terraform directory")

terraform_plan = subprocess.run(
    ["terraform plan"], shell=True, stderr=subprocess.PIPE, stdout=subprocess.PIPE)
if terraform_plan.returncode != 0:
    print(terraform_plan.stderr.decode('utf8'))
    exit("Terraform plan error!")
print(terraform_plan.stdout.decode("utf8"))

terraform_apply = subprocess.run(
    ["terraform apply -auto-approve"], shell=True, stderr=subprocess.PIPE, stdout=subprocess.PIPE)
if terraform_apply.returncode != 0:
    print(terraform_apply.stderr.decode("utf8"))
    tf_destroy()
print(terraform_apply.stdout.decode('utf8'))


for index, item in enumerate(terraform_apply.stdout.decode('utf8').splitlines()):
    if item.find("API externally - ") != -1:
        try:
            ip = re.search(r"\d+.\d+.\d+.\d+", item).group(0)
        except:
            ip = None
            exit("Something went wrong in get ipaddres!")

os.chdir("..")

with open("/etc/hosts") as file:
    hosts_file_ = file.readlines()

with open("hosts_backup.txt", 'w', encoding='utf8') as file:
    file.writelines(hosts_file_)

index_to_del = list()
for index, item in enumerate(hosts_file_):
    if item.find(f"api.{cluster_name}.{dns_zone}.ru") != -1:
        index_to_del.append(index)
index_to_del.reverse()
if len(index_to_del) != 0:
    for index_del in index_to_del:
        hosts_file_.pop(index_del)

hosts_file_.append(f"\n{ip}\tapi.{cluster_name}.{dns_zone}.ru")
with open('temp_hosts.txt', 'w', encoding='utf8') as file:
    file.writelines(hosts_file_)
write_hosts = subprocess.run(["sudo su -c 'cat ./temp_hosts.txt > /etc/hosts'"],
                             shell=True, stderr=subprocess.PIPE, stdout=subprocess.PIPE)
if write_hosts.returncode != 0:
    exit("Something went wrong (write data to /etc/hosts)")
os.remove("temp_hosts.txt")


print("We wait until the bootstrap node is installed for 10 minutes.")
time.sleep(600)
os.system("bash ./scripts/wait-for-bootstrap.sh")

print("Bootstrapping complete!")
time.sleep(120)
print("Deleting bootstrap node!")
with open("./terraform/terraform.tfvars") as file:
    data_tftvars = file.readlines()
for index, item in enumerate(data_tftvars):
    if item.find("bootstrap_count") != -1:
        data_tftvars[index] = f"""bootstrap_count    = 0\n"""
with open("./terraform/terraform.tfvars", 'w', encoding='utf8') as file:
    file.writelines(data_tftvars)
os.chdir("terraform")
terraform_apply = subprocess.run(
    ["terraform apply -auto-approve"], shell=True, stderr=subprocess.PIPE, stdout=subprocess.PIPE)
if terraform_apply.returncode != 0:
    print(terraform_apply.stderr.decode("utf8"))
    tf_destroy()
print(terraform_apply.stdout.decode('utf8'))
print("Bootsrap node deleted")

os.chdir("..")

print("We are waiting for 10 minutes to install the master node.")
time.sleep(600)
print("We sign certificates.")
os.system("bash ./scripts/sign-csr-all.sh")

print("We are waiting for the working node to be installed.!")
os.system("bash ./scripts/wait-for-install.sh")

print("Installation complete and we did it!")
