#!/bin/bash
set -euo pipefail

echo "Terraform Deployment Initiating"
echo "Standby..."
terraform apply -auto-approve | grep -E "Apply complete"
terraform output > outputs.txt 
echo ""

cd ~/ha-project/ansible

echo "Configuring NAT"
ansible-playbook plays/ami-nat.yml
ansible-playbook plays/ami-reboot.yml
echo ""

echo "Update/Upgrade Private EC2 Instances"
# ansible-playbook plays/ssm-check.yml -l ssm_hosts
# ansible-playbook plays/mirror-check.yml -l ssm_hosts
ansible-playbook plays/update.yml -l ssm_hosts
ansible-playbook plays/reboot.yml -l ssm_hosts
echo ""

cat ~/ha-project/outputs.txt
echo ""
echo "Deployment and Configuration Complete!"
