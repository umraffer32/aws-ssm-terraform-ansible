# Problems, Solutions, and Optimizations

## Problem: <short title>

### Context
What were you trying to do?

### Issue
What actually went wrong?

### Root Cause
Why did it happen?

### Solution
What fixed it?

### Takeaway
What did you learn / how will you avoid it next time?

### Verification
How did you confirm it was fixed?

########################################################################

## Problem: Ansible SSM connection failing with `NoneType` and `TargetNotConnected`

### Context
Attempting to manage private EC2 instances using Ansible over AWS SSM with a dynamic inventory (`aws_ec2`) and no SSH/public IP access.

---

### Issue
- Ansible `ping` module failed with:
  - `expected string or bytes-like object, got 'NoneType'`
  - `TargetNotConnected`
- SSM manual sessions worked, but Ansible did not
- S3 access initially failed
- Dynamic inventory hosts were not behaving as expected

---

### Root Cause
Multiple layered issues:

1. **Missing NAT / improper outbound routing**
   - Instances could not reach S3 → SSM file transfer failed

2. **SSM S3 bucket region mismatch**
   - Bucket created in different region than instances

3. **Instance not in correct inventory group**
   - Missing `Role=ssm-hosts` tag → `group_vars` not applied

4. **Reserved variable conflict (`tags`)**
   - AWS inventory plugin exposed `tags`, conflicting with Ansible reserved keyword

5. **Dynamic inventory vs static test mismatch**
   - Simple inventory worked → isolated issue to inventory/plugin config

---

### Solution
- Built NAT instance and disabled source/dest check
- Ensured outbound internet access for private subnet
- Recreated S3 bucket in correct region (`us-west-2`)
- Added required tag:
  ```
  Role = ssm-hosts
  ```
- Updated inventory:
  - Used `hostvars_prefix: aws_` to eliminate `tags` warning
  - Updated keyed groups to use `aws_tags.Role`
- Verified group membership with:
  ```
  ansible-inventory --graph
  ```
- Validated SSM + Ansible using a minimal static inventory before returning to dynamic

---

### Takeaway
- Always isolate layers:
  - Infra (networking)
  - Connectivity (SSM)
  - Tooling (Ansible)
- If a simple/static test works but dynamic fails → problem is inventory, not infra
- SSM with Ansible **requires S3 + outbound connectivity**
- AWS dynamic inventory can introduce subtle variable conflicts (`tags`)
- Tag-based grouping directly impacts variable inheritance (`group_vars`)

---

### Verification
- Confirmed SSM connectivity manually:
  ```
  aws ssm start-session --target <instance-id>
  ```

- Verified S3 access from instance:
  ```
  curl https://s3.amazonaws.com
  ```

- Confirmed correct inventory grouping:
  ```
  ansible-inventory -i aws_ec2.yml --graph
  ```

- Successful Ansible execution:
  ```
  ansible -i aws_ec2.yml ssm_hosts -m ping
  ```

- Playbook ran successfully and idempotently:
  ```
  changed=0 on second run
  ```

########################################################################  