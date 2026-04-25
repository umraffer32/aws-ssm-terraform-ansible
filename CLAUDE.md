# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Terraform + Ansible lab that provisions a private AWS VPC and manages EC2 instances exclusively via AWS Systems Manager (SSM) — no SSH, no open ports, no bastion. Ansible connects over SSM using a dynamic inventory (`aws_ec2` plugin).

**Region:** `us-west-2`

## Architecture

```
Internet → IGW → Public Subnet (10.0.100.0/24) → NAT Instance (Debian 13, t2.micro)
                                                          ↕ (forwards traffic)
                                    Private Subnet (10.0.1.0/24) → SSM Hosts (Ubuntu 24.04, t2.micro × N)

Management: local machine → AWS SSM Session Manager → instances (no port 22)
Ansible:    SSM proxy connection via community.aws.aws_ssm → dynamic inventory groups
```

- NAT instance has `source_dest_check = false` and bootstraps iptables MASQUERADE via `user_data`
- Private instances have zero inbound security group rules — outbound only through NAT
- IMDSv2 enforced (`http_tokens = "required"`) on the NAT instance
- Both instance types use the `SSM-EC2` IAM instance profile (must exist in AWS before apply)

## Key Files

| File | Purpose |
|---|---|
| `compute.tf` | EC2 instances (NAT + ssm_hosts), IAM profiles, user_data bootstrap |
| `network.tf` | VPC, public/private subnets, IGW, route tables |
| `security.tf` | Security groups (NAT allows inbound from private SG; private has egress only) |
| `data.tf` | AMI lookups — Debian 13 (NAT), Ubuntu 24.04 (hosts), Amazon Linux 2023 (unused) |
| `variables.tf` | `ssm_host_count` — number of private hosts to deploy |
| `terraform.tfvars` | Variable overrides (not committed; gitignored) |
| `outputs.tf` | Prints `aws ssm start-session` commands for all instances after apply |
| `deploy.sh` | Full automated deploy: `terraform apply` → Ansible NAT config → Ansible host update |
| `wipe.sh` | `terraform destroy --auto-approve` |
| `ansible/ansible.cfg` | SSM proxy config; vault password from `~/.vault_pass.txt` |
| `ansible/aws_ec2.yml` | Dynamic inventory — groups hosts by `Role` tag (`ssm_hosts`, `ssm_nat`) |
| `ansible/plays/` | Playbooks: update, reboot, NAT config, Tailscale install, SSM check |

## Common Commands

**Deployment:**
```bash
# Full automated deploy (runs terraform apply + all Ansible plays)
./deploy.sh

# Manual Terraform workflow
terraform init                  # Initialize backend
terraform validate              # Check syntax and references
terraform plan                  # Preview changes
terraform apply                 # Apply infrastructure
terraform fmt -recursive        # Format all .tf files

# Inspect state
terraform state list
terraform state show <resource>
```

**Connecting & Management:**
```bash
# Connect to an instance (outputs printed by 'terraform apply')
aws ssm start-session --target <instance-id>

# Verify NAT is working from an instance
curl https://google.com
cat /proc/sys/net/ipv4/ip_forward   # Should return 1
sudo iptables -t nat -L -n -v
```

**Ansible:**
```bash
# Verify dynamic inventory structure
ansible-inventory -i ansible/aws_ec2.yml --graph
ansible-inventory -i ansible/aws_ec2.yml --host <instance-id>

# Test SSM connectivity via Ansible
ansible -i ansible/aws_ec2.yml ssm_hosts -m ping
ansible -i ansible/aws_ec2.yml ssm_nat -m ping

# Run a playbook
ansible-playbook ansible/plays/update.yml -l ssm_hosts
ansible-playbook ansible/plays/aws-tailscale.yml

# Edit encrypted secrets
ansible-vault edit ansible/group_vars/ssm_hosts/vault.yml

# Run playbook with vault password
ansible-playbook ansible/plays/update.yml --ask-vault-pass
```

**Teardown:**
```bash
./wipe.sh  # Runs 'terraform destroy --auto-approve'
```

## Important Constraints

- **IAM profile `SSM-EC2` must exist in AWS** before `terraform apply` — it's referenced by name in `compute.tf`, not created here.
- **S3 bucket for SSM file transfer must be in `us-west-2`** — region mismatch breaks Ansible SSM connections. See PROBLEMS.md #1.
- **Ansible Vault password** stored at `~/.vault_pass.txt` is required for playbooks using encrypted vars. Configure via `ansible.cfg` setting `vault_password_file`.
- `boto3` and `botocore` Python packages required locally for the dynamic inventory plugin.
- AWS SSM Session Manager plugin must be installed locally for `aws ssm start-session` and the Ansible SSM connection plugin.
- `hostvars_prefix: aws_` in `aws_ec2.yml` avoids collision with Ansible's reserved `tags` variable — do not remove it (see PROBLEMS.md #3).
- Tag `Role=ssm-hosts` on private instances is what puts them in the `ssm_hosts` inventory group, enabling `group_vars` to apply (see PROBLEMS.md #2).
- Dynamic inventory `compose:` block requires double-quoted string literals: `ansible_connection: '"community.aws.aws_ssm"'` (see PROBLEMS.md #4).

## Terraform State Management

- `terraform.tfstate` and `terraform.tfstate.backup` are committed to repo (not `.gitignored`).
- For team collaboration, migrate to remote state (S3 backend with DynamoDB locking) — see README "What I'd Add Next".

## Scaling

Change host count without touching resource definitions:

```hcl
# terraform.tfvars
ssm_host_count = 5
```

Then re-run `terraform plan` and `terraform apply`.

## Secrets

Sensitive values (e.g., Tailscale auth key) live in `ansible/group_vars/ssm_hosts/vault.yml`, encrypted with Ansible Vault. Edit with:

```bash
ansible-vault edit ansible/group_vars/ssm_hosts/vault.yml
```

## Troubleshooting

See [PROBLEMS.md](./PROBLEMS.md) for detailed solutions to common issues:
- Ansible SSM connection failures and `TargetNotConnected` errors
- Missing NAT and S3 region mismatches
- Missing inventory tags
- Dynamic inventory variable conflicts
- `compose:` quoting quirks in `aws_ec2.yml`
