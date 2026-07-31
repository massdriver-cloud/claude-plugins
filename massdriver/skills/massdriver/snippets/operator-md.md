---
templating: mustache
---

# <Bundle Name> Runbook

Operational procedures for `{{id}}`. Every section is written for the engineer on call:
symptom → diagnosis → fix, with runnable commands.

## Health Check

```bash
# Replace with the fastest command that proves this instance is healthy
aws rds describe-db-instances --db-instance-identifier {{resources.my_resource.id}} \
  --query 'DBInstances[0].DBInstanceStatus'
```

{{#dependencies.database}}
## Connect to the Database

```bash
psql -h {{dependencies.database.auth.hostname}} -d {{dependencies.database.auth.database}}
```
{{/dependencies.database}}

## Rotate Credentials

1. Exact steps an operator runs, with real commands.
2. Interpolate live values into the commands rather than describing where to find them.
3. End with a verification step.

## Failure Modes

### Connection timeouts

1. Diagnosis: check security group / network path
2. Fix
3. Verify

### Permission denied

1. Diagnosis: verify IAM policies and resource permissions
2. Fix
3. Verify

## Escalation

- **Team**: Platform Engineering
- **Slack**: #platform-support
