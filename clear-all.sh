#!/bin/sh
echo "Cleaning all to default state..."
rm -rf ./bin/
rm -rf ./images/
rm -rf ./okd-ignition/
rm -rf ./secrets/
rm -rf ./temp/
rm -r ./terraform/.terraform
rm ./terraform/.terraform.lock.hcl
rm ./terraform/terraform.tfstate
rm ./terraform/terraform.tfstate.backup
rm ./hosts_backup.txt
