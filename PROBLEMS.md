## Ansible SSM connection failing with `NoneType` and `TargetNotConnected`

### 1. Missing NAT and S3 bucket region mismatch

Ansible `ping` module failed with `TargetNotConnected` and `expected string or bytes-like object, got 'NoneType'`. Manual SSM sessions worked, but Ansible failed. Root cause: SSM agent on instances needs to download files from S3 before running Ansible connections, but instances had no outbound internet access and the S3 bucket was in a different region.

**Fix:** Build a NAT instance in the public subnet with `source_dest_check = false` and iptables MASQUERADE rules to forward traffic from the private subnet. Configure instances to route outbound traffic through the NAT. Recreate the S3 bucket in the same region as the instances (`us-west-2`).

**Verify:** Test outbound connectivity from an instance:

```bash
# From the instance via SSM
aws ssm start-session --target <instance-id>
curl https://s3.amazonaws.com
```

Confirm Ansible can now connect:

```bash
ansible -i aws_ec2.yml ssm_hosts -m ping
```

### 2. Missing `Role=ssm-hosts` tag on instances

Instances were not appearing in the `ssm_hosts` inventory group, so `group_vars/ssm_hosts` was never applied to them. The dynamic inventory plugin groups instances using the `aws_ec2.yml` keyed groups configuration, which looks for the `Role` tag.

**Fix:** Add the required tag to all SSM host instances:

```
Role = ssm-hosts
```

Update the inventory keyed groups configuration to use the tag:

```yaml
keyed_groups:
  - key: aws_tags.Role
    prefix: ""
```

**Verify:** Check that instances are correctly grouped:

```bash
ansible-inventory -i aws_ec2.yml --graph
# Should show ssm_hosts group populated with instance IDs
```

### 3. Reserved variable conflict with `tags` in dynamic inventory

The AWS `aws_ec2` inventory plugin exposes a `tags` variable for each host, which conflicts with Ansible's reserved `tags` keyword (used for play/task tagging). This caused warnings and unexpected behavior.

**Fix:** Set `hostvars_prefix: aws_` in the `aws_ec2.yml` inventory configuration to prefix all AWS-specific variables:

```yaml
plugin: aws_ec2
hostvars_prefix: aws_
```

Now AWS tags are accessed as `aws_tags` instead of `tags`.

**Verify:** Inspect hostvars for a host to confirm the prefix is applied:

```bash
ansible-inventory -i aws_ec2.yml --host <instance-id>
# Should show "aws_tags": {...} without "tags" collision
```

Check for any remaining variable conflicts by running a play:

```bash
ansible-playbook ansible/plays/update.yml -l ssm_hosts
# Should run without variable warnings
```

## aws_ec2 inventory plugin: `compose` quirks

### 1. String literals in `compose` need double quoting

The `compose:` block evaluates every value as a **Jinja2 expression**, not a literal string. Writing:

```yaml
compose:
  ansible_connection: community.aws.aws_ssm
```

causes Jinja2 to parse `community.aws.aws_ssm` as a variable lookup (`community` → attribute `aws` → attribute `aws_ssm`), which doesn't exist. Ansible silently falls back to SSH and fails with `Could not resolve hostname i-xxxx: Temporary failure in name resolution`.

**Fix:** wrap literals so the inner quotes survive YAML parsing into Jinja2:

```yaml
ansible_connection: '"community.aws.aws_ssm"'
```

- Outer `' '` → YAML string
- Inner `" "` → Jinja2 string literal

Applies to any literal string set via `compose` (e.g. `ansible_user: '"ubuntu"'`).

### 2. `ansible_host: instance_id` is unnecessary for SSM

`ansible_host` tells Ansible where to make a **network connection** (SSH target IP/DNS). The SSM connection plugin doesn't open a network connection from the control node — it talks to the AWS SSM API, which routes to the agent on the instance. SSM only needs the **instance ID**, which it pulls from the inventory hostname.

Setting `ansible_host: instance_id` is harmless but redundant; safe to remove.

### Verify

Confirm hostvars resolved correctly before running a play:

```bash
# Inspect what the inventory plugin produced for a host
ansible-inventory -i aws_ec2.yaml --host i-062e1b05ba7a0fb14

# Expect to see:
#   "ansible_connection": "community.aws.aws_ssm"
# If you see the connection key missing or set to a weird value,
# the quoting bug is back.
```

Then a quick connectivity check:

```bash
ansible all -i aws_ec2.yaml -m ping
# All hosts should return "ping": "pong" via SSM,
# with no SSH "Could not resolve hostname" errors.
```