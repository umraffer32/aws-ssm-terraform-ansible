# Terraform + Ansible via AWS SSM
### VPC with NAT Instance and Private EC2 Instances
 
A fully automated AWS environment built with Terraform and configured with Ansible over AWS Systems Manager (SSM) — **no open ports, no SSH keys, no bastion host**.
 
This project provisions a custom VPC with public/private subnets, a **Debian 13** NAT instance bootstrapped entirely via `user_data`, and uses SSM Session Manager as the sole access method for all EC2 instances. Ansible connects through SSM using a dynamic inventory (`aws_ec2` plugin), and secrets are managed via Ansible Vault.


## Architectural Layout

![Architecture Diagram](./images/architecture.png)

**VPC CIDR:** `10.0.0.0/16` | **Region:** `us-west-2`
 
| Subnet | CIDR | AZ |
|---|---|---|
| Public | `10.0.100.0/24` | us-west-2a |
| Private | `10.0.1.0/24` | us-west-2a |
 
**Traffic flow:**
- Private instances → NAT instance → IGW → Internet
- Management access → AWS SSM Session Manager (no port 22, no keypairs)
- Ansible → SSM proxy → EC2s via dynamic inventory
---
 
## Cost Considerations
 
A NAT Gateway would be the preferred solution in production, but costs ~$32/month minimum before data transfer. SSM interface endpoints (ssm, ssmmessages, ec2messages) were also evaluated but are only marginally cheaper. For this lab — with frequent provisioning, updating, and teardown — a **`t2.micro` Debian NAT instance** provides the most economical approach at a fraction of the cost.
 
---
 
## Tech Stack
 
| Tool | Purpose |
|---|---|
| **Terraform** | Infrastructure provisioning (VPC, subnets, EC2, IAM, security groups) |
| **Ansible** | Configuration management and operational playbooks |
| **AWS SSM** | Secure instance access — replaces SSH entirely |
| **Ansible Vault** | Secrets encryption at rest |
| **Tailscale** | WireGuard-based mesh VPN overlay |
| **Debian 13** | NAT instance OS (custom NAT, not managed NAT Gateway) |
| **Ubuntu 24.04 LTS** | Private EC2 host OS |
 
---
 
## Project Structure
 
```
.
├── ansible/
│   ├── group_vars/
│   │   ├── ssm_hosts/
│   │   │   ├── main.yml          # Vars for private EC2 hosts
│   │   │   └── vault.yml         # Encrypted secrets (Ansible Vault)
│   │   └── ssm_nat/
│   │       └── main.yml          # Vars specific to the NAT instance
│   ├── plays/
│   │   ├── ami-nat.yml           # Configure NAT (iptables, ip_forward)
│   │   ├── ami-reboot.yml        # Reboot NAT after configuration
│   │   ├── ami-update-ssmcheck.yml  # Update + verify SSM pre-AMI
│   │   ├── aws-tailscale.yml     # Install and configure Tailscale
│   │   ├── mirror-check.yml      # Verify package mirror availability
│   │   ├── nat.yml               # NAT instance playbook
│   │   ├── reboot.yml            # Safe reboot with reconnect wait
│   │   ├── ssm-check.yml         # Verify SSM agent status
│   │   └── update.yml            # Full system update
│   ├── ansible.cfg               # SSM proxy config, inventory settings
│   └── aws_ec2.yml               # Dynamic inventory (aws_ec2 plugin)
├── compute.tf                    # EC2 instances, IAM profiles, user_data
├── data.tf                       # AMI data sources (Debian 13, Ubuntu 24.04, AL2023)
├── network.tf                    # VPC, subnets, IGW, route tables, associations
├── outputs.tf                    # SSM connect commands for all instances
├── security.tf                   # Security groups (NAT and private hosts)
├── variables.tf                  # Input variables (ssm_host_count)
├── terraform.tfvars              # Variable overrides (gitignored)
├── deploy.sh                     # Full deploy + configure automation script
├── wipe.sh                       # Teardown script
└── PROBLEMS.md                   # Issues encountered and solutions
```
 
---
 
## Key Design Decisions
 
### Debian NAT instance over managed NAT Gateway
AWS Managed NAT Gateway costs ~$32/month at minimum. A `t2.micro` Debian 13 instance running NAT via `iptables` and `ip_forward` costs a fraction of that. The NAT instance is bootstrapped entirely via `user_data` — no manual configuration, fully reproducible, version-controlled. `source_dest_check` is disabled in Terraform so the instance can forward traffic it didn't originate.
 
The `user_data` bootstrap:
1. Detects the primary network interface dynamically (`ip route`)
2. Installs the SSM agent (so the NAT instance is itself manageable via SSM)
3. Enables `net.ipv4.ip_forward` persistently via `sysctl`
4. Adds `iptables` MASQUERADE and FORWARD rules
5. Persists rules across reboots with `netfilter-persistent`
### SSM over SSH
- No open port 22 — zero inbound rules on the private security group
- No keypair management or distribution
- IAM controls who can access which instances
- Session activity is auditable via CloudWatch/S3
- Works natively through the NAT instance without a bastion
### IMDSv2 enforced
The NAT instance has `http_tokens = "required"`, enforcing IMDSv2 on the instance metadata service. This prevents SSRF-based metadata credential theft attacks.
 
### Dynamic Ansible inventory
The `aws_ec2` plugin queries the AWS API at runtime and groups hosts by tag (`Role=ssm-hosts` and `Role=ssm-nat`). No hardcoded IPs — the inventory stays accurate across destroys and rebuilds. Uses `hostvars_prefix: aws_` to avoid conflicts with Ansible's reserved `tags` variable.
 
### Configurable host count
`ssm_host_count` in `variables.tf` controls how many private EC2s are deployed. Set it in `terraform.tfvars` to scale without touching resource definitions.
 
### Ansible Vault for secrets
Credentials and tokens live in `group_vars/ssm_hosts/vault.yml`, encrypted at rest. The entire repo can be public without exposing sensitive values.
 
---
 
## Prerequisites
 
- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Ansible >= 2.12
- Python packages: `boto3`, `botocore` (required for dynamic inventory)
- AWS SSM Session Manager plugin installed locally
- Ansible Vault password
**IAM managed policy required on EC2 instances:**
- `AmazonSSMManagedInstanceCore`
**IAM permissions required for your local AWS user:**
- `ssm:StartSession`
- `ssm:DescribeInstanceInformation`
- `ec2:DescribeInstances`
---
 
## Deployment
 
### 1. Clone and configure
 
```bash
git clone https://github.com/umraffer32/aws-ssm-terraform-ansible.git
cd aws-ssm-terraform-ansible
```
 
Set your desired host count:
 
```bash
# terraform.tfvars
ssm_host_count = 5
```
 
### 2. Deploy and configure (automated)
 
```bash
./deploy.sh
```
 
This script:
1. Runs `terraform apply` and captures outputs to `outputs.txt`
2. Configures the NAT instance — iptables rules and IP forwarding (`ami-nat.yml`)
3. Reboots the NAT instance (`ami-reboot.yml`)
4. Runs system updates on all private hosts (`update.yml`)
5. Reboots private hosts (`reboot.yml`)
6. Prints SSM connect commands for all instances
### 3. Manual deployment (step by step)
 
```bash
terraform init
terraform plan
terraform apply
```
 
Verify SSM connectivity:
 
```bash
ansible-playbook ansible/plays/ssm-check.yml
```
 
Configure NAT instance:
 
```bash
ansible-playbook ansible/plays/ami-nat.yml
ansible-playbook ansible/plays/ami-reboot.yml
```
 
Update and configure private hosts:
 
```bash
ansible-playbook ansible/plays/update.yml -l ssm_hosts
ansible-playbook ansible/plays/reboot.yml -l ssm_hosts
ansible-playbook ansible/plays/aws-tailscale.yml
```
 
### 4. Connect to instances
 
After `terraform apply`, SSM connect commands are printed automatically via Terraform outputs:
 
```bash
# NAT instance
aws ssm start-session --target <nat-instance-id>
 
# Private hosts
aws ssm start-session --target <host-instance-id>
```
 
### 5. Teardown
 
```bash
./wipe.sh
```
 
---
 
## Verify NAT is Working
 
From the NAT instance via SSM:
 
```bash
# Confirm IP forwarding is active
cat /proc/sys/net/ipv4/ip_forward        # should return 1
 
# Confirm iptables MASQUERADE rule
sudo iptables -t nat -L -n -v
 
# Confirm FORWARD chain
sudo iptables -L FORWARD -n -v
```
 
From a private EC2 instance via SSM:
 
```bash
# Confirm outbound internet through NAT
curl https://google.com
```
 
---
 
## Ansible Vault
 
Secrets are stored encrypted in `ansible/group_vars/ssm_hosts/vault.yml`.
 
```bash
# Create vault
ansible-vault create group_vars/ssm_hosts/vault.yml
 
# Edit vault
ansible-vault edit group_vars/ssm_hosts/vault.yml
 
# Run playbook with vault
ansible-playbook plays/update.yml --ask-vault-pass
 
# Or use a password file
ansible-playbook plays/update.yml --vault-password-file ~/.vault_pass
```
 
---
 
## Dynamic Inventory
 
Verify inventory grouping after deploy:
 
```bash
ansible-inventory -i aws_ec2.yml --graph
```
 
Expected output:
 
```
@all:
  |--@ssm_hosts:
  |  |--i-xxxxxxxxxxxxxxxxx
  |  |--i-xxxxxxxxxxxxxxxxx
  |--@ssm_nat:
  |  |--i-xxxxxxxxxxxxxxxxx
```
 
Test connectivity across all hosts:
 
```bash
ansible -i aws_ec2.yml ssm_hosts -m ping
```
 
---
 
## Problems Encountered
 
See [`PROBLEMS.md`](./PROBLEMS.md) for a detailed log of issues hit during development and how they were resolved — covering SSM connectivity failures, S3 region mismatches, dynamic inventory variable conflicts, and NAT routing issues.
 
---
 
## What I'd Add Next
 
- **Remote Terraform state** — S3 backend with DynamoDB locking for team collaboration
- **NAT instance HA** — Lambda + CloudWatch Events to detect NAT failure and update the private route table automatically
- **Terraform modules** — refactor network and compute into reusable, parameterized modules
- **CI/CD pipeline** — GitHub Actions to run `terraform plan` on PRs, `terraform apply` on merge to main
- **Multi-AZ** — spread private hosts across availability zones for resilience
- **VPC Flow Logs** — enable for traffic visibility and security auditing
