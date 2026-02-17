# Post-Deployment Compliance Review

After a successful deployment, review Checkov findings from the deployment logs and work through them systematically.

## Workflow

**1. Extract Checkov findings:**
```bash
mass logs <deployment-id> 2>&1 | grep -E "Check:|FAILED"
```

**2. Create TODO list** in the bundle's directory (e.g., `bundles/aws-rds-mysql/TODO.md`):

```markdown
# Bundle Improvements

Security improvements identified by Checkov.

## aws-rds-mysql

- [ ] **HIGH** - **CKV_XXX_123** - Description of the issue
  - How to fix it
  - Why it matters

- [ ] **MEDIUM** - **CKV_XXX_456** - Description
  - Implementation notes

- [x] **IGNORE** - **CKV_XXX_789** - Description
  - Reason for ignoring (e.g., intentional design decision)
```

**3. Work through the issues:**

| Priority | Action |
|----------|--------|
| **HIGH** | Attempt to fix by hardcoding secure defaults or exposing as params |
| **MEDIUM** | Attempt to fix if straightforward; otherwise document why deferred |
| **LOW** | Add to `.checkov.yml` skip list with comment explaining why |
| **IGNORE** | Add to `.checkov.yml` skip list - intentional design decisions |

**4. For issues to skip**, create/update `src/.checkov.yml`:
```yaml
skip-check:
  # LOW: Security group egress - RDS requires outbound for AWS API calls
  - CKV_AWS_382
  # LOW: SNS encryption - alarm metadata not sensitive
  - CKV_AWS_26
```

**5. For issues to fix**, update the Terraform code:
```hcl
# HIGH: CKV2_AWS_69 - Require SSL connections
resource "aws_db_parameter_group" "main" {
  parameter {
    name  = "require_secure_transport"  # MySQL
    value = "1"
  }
  # or
  parameter {
    name  = "rds.force_ssl"  # PostgreSQL
    value = "1"
  }
}
```

**6. Republish and redeploy** to verify fixes:
```bash
mass bundle publish --development
mass pkg deploy <package> -m "Fix CKV2_AWS_69: Enable SSL enforcement"
```

## Priority Ratings

| Priority | Criteria | Examples |
|----------|----------|----------|
| **HIGH** | Security vulnerability, data exposure risk, or compliance requirement | Encryption disabled, public exposure, missing auth |
| **MEDIUM** | Best practice, observability, or operational improvement | Logging disabled, no monitoring, missing tags |
| **LOW** | Optimization or nice-to-have enhancement | VPC endpoints, cost optimization |
| **IGNORE** | Intentional design decision or not applicable | Public IPs on public subnets, Multi-AZ disabled for dev |

## Common Checkov Findings by Category

| Category | Typical Findings | Typical Fix |
|----------|------------------|-------------|
| **Encryption** | KMS keys, encryption at rest, TLS | Enable encryption, add parameter for SSL |
| **Logging** | CloudWatch logs, flow logs, audit trails | Enable log exports, add log group |
| **Access Control** | IAM auth, security groups, public access | Restrict ingress, disable public access |
| **Backup/DR** | Deletion protection, snapshots, Multi-AZ | Add params for user control |
| **Monitoring** | Enhanced monitoring, Performance Insights | Enable with instance class checks |

Always document the rationale for IGNORE decisions - future maintainers need to understand why a security recommendation was intentionally skipped.
