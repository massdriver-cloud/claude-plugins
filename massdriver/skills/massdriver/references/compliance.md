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
| **LOW** | Document for future improvement; do NOT skip unless truly irrelevant |
| **SKIP** | Add to `.checkov.yml` ONLY if check is irrelevant across ALL environments (see Skip-Check Rules) |

**4. For issues to skip**, create/update `src/.checkov.yml`:
```yaml
skip-check:
  # Security group egress required for AWS API connectivity
  - CKV_AWS_382
  # Aurora-only check, not applicable to standard RDS instances
  - CKV_AWS_162
```

> **CRITICAL**: Only skip checks that are genuinely irrelevant across ALL environments including production. A skipped check is invisible to `halt_on_failure`. See the Skip-Check Rules in SKILL.md for the full policy.

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
| **LOW** | Optimization or nice-to-have; do not skip unless truly irrelevant | VPC endpoints, cost optimization |
| **SKIP** | Check is irrelevant across ALL environments (not applicable to resource type, by-design infrastructure, or out-of-scope dependency) | Aurora-only checks on standard RDS, SG egress for AWS API connectivity |

## Skip-Check Rules (STRICT)

A skipped check is skipped EVERYWHERE — `halt_on_failure` does NOTHING for skipped checks.

**ONLY skip checks that are genuinely irrelevant across ALL environments including production.**

**Valid reasons to skip:**
- Check is not applicable to the resource type (e.g., Aurora-only checks on standard RDS)
- Check targets infrastructure that is by design (e.g., SG egress for AWS service connectivity, public IPs on public subnets)
- Check requires infrastructure outside the bundle's scope (e.g., Lambda rotator for secret rotation)

**NEVER skip a check for something configurable via params** (e.g., multi-AZ, deletion protection, enhanced monitoring, TLS, automatic failover). If a user can toggle it, let checkov flag it naturally. `halt_on_failure` enforces compliance in production while giving users freedom in non-prod.

**Invalid reasons to skip:**
- "Dev preset has it disabled for cost savings" — NO, the bundle runs in prod too
- "halt_on_failure enforces this in production" — NO, skipped checks are invisible to halt_on_failure
- "This bundle targets dev environments" — NO, all bundles eventually run in production

**Comments in `.checkov.yml`** must be factual about WHY the check is irrelevant. Never reference environments, presets, dev/prod distinctions, or halt_on_failure as justification.

**When in doubt, DO NOT skip.** Let the check fail, and let `halt_on_failure` do its job.

## Common Checkov Findings by Category

| Category | Typical Findings | Typical Fix |
|----------|------------------|-------------|
| **Encryption** | KMS keys, encryption at rest, TLS | Enable encryption, add parameter for SSL |
| **Logging** | CloudWatch logs, flow logs, audit trails | Enable log exports, add log group |
| **Access Control** | IAM auth, security groups, public access | Restrict ingress, disable public access |
| **Backup/DR** | Deletion protection, snapshots, Multi-AZ | Add params for user control (let halt_on_failure enforce in prod) |
| **Monitoring** | Enhanced monitoring, Performance Insights | Enable with instance class checks |

Comments in `.checkov.yml` must state factual reasons why a check is irrelevant — never reference environments or halt_on_failure as justification for skipping.
