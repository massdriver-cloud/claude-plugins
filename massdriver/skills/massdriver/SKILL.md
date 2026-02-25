---
name: massdriver
description: Develop and test Massdriver infrastructure bundles. Operates in two modes - FULL (interactive deploy loop with compliance remediation) or BUILD-ONLY (local validation without publishing). Auto-activates when working with massdriver.yaml, bundles/, artifact-definitions/, or platforms/ directories. Use when creating new bundles, modifying IaC, testing deployments, or fixing compliance findings.
---

# Massdriver Bundle Development

You are helping develop infrastructure bundles for Massdriver. This skill provides two operational modes, patterns, and workflows for bundle development.

## Table of Contents

- [Operational Modes](#operational-modes)
- [Full Mode Workflow](#full-mode-workflow)
- [Build-Only Mode Workflow](#build-only-mode-workflow)
- [Core Concepts](#core-concepts)
- [Bundle Design Philosophy](#bundle-design-philosophy)
- [Bundle Scoping and Resource Lifecycle](#bundle-scoping-and-resource-lifecycle)
- [Schema Validation](#schema-validation)
- [Critical Rules](#critical-rules)
- [File Responsibilities](#file-responsibilities)
- [Common Patterns](#common-patterns)
- [Checkov Security Configuration](#checkov-security-configuration)
- [Validation Checklist](#validation-checklist)
- [Common Mistakes & Fixes](#common-mistakes--fixes)
- [Commands Reference](#commands-reference)

**Reference Files:**
- [PATTERNS.md](./PATTERNS.md) - Complete bundle and artifact examples
- [references/alarms.md](./references/alarms.md) - Adding monitoring alarms (AWS/GCP/Azure)
- [references/compliance.md](./references/compliance.md) - Post-deployment Checkov remediation
- [snippets/](./snippets/) - Copy-paste templates

---

## Operational Modes

When starting bundle work, determine the mode:

### Full Mode (Deploy Loop)
**Use when:** Testing bundles end-to-end, validating compliance, iterating on real infrastructure.

The full mode workflow:
1. Gather requirements interactively
2. Design bundle with presets
3. Build, publish (development only), and deploy
4. Monitor compliance findings, iterate until clean
5. Never publish stable without explicit human authorization

### Build-Only Mode
**Use when:** Developing locally, validating syntax, no cloud access needed.

The build-only mode workflow:
1. `mass bundle build`
2. `tofu init && tofu validate`
3. Iterate on code until validation passes
4. No publishing, no deployments

---

## Full Mode Workflow

### Phase 1: Requirements Gathering

Before writing code, gather these inputs through conversation:

**1. Use Case Description**
- What problem does this bundle solve?
- Who is the target user (developer, data scientist, ops)?
- What's the operational context (dev/staging/prod)?

**2. Resource Scoping**
Based on the use case, suggest appropriate cloud resources:
- Check existing bundles: `mass bundle list`
- Check existing artifacts: `mass def list`
- Propose resources that fit the lifecycle tier (foundational/stateful/compute)

**3. Preset Design**
Design `params.examples` presets for common configurations:
```yaml
params:
  examples:
    - __name: Development
      instance_type: "t3.small"
      storage_gb: 20
      multi_az: false
    - __name: Production
      instance_type: "r6g.large"
      storage_gb: 100
      multi_az: true
```

**4. Compliance Strategy**
Understand compliance requirements:
- Which severity levels matter? (HIGH always, MEDIUM usually, LOW optional)
- Any checks to hardcode vs make user-configurable?
- Note: Full findings emerge during deployment - iterate as they appear

**5. Project/Environment Setup**
Confirm deployment target:
- User provides existing project, or create one: `mass project create <slug> --name "<Name>"`
- User provides environment, or create one: `mass env create <slug> --name "<Name>"`
- Environment must have cloud credential artifact attached (user sets up in UI)

### Phase 2: Bundle Development

Follow the bundle creation workflow:

1. **Scaffold the bundle:**
   ```bash
   mkdir -p bundles/my-bundle/src
   ```

2. **Check/create artifact definitions:**
   - Run `mass def list` to see existing definitions
   - If bundle needs a new artifact type, create `artifact-definitions/<name>/massdriver.yaml`
   - Publish new definitions: `mass definition publish artifact-definitions/<name>/massdriver.yaml`
   - **Warning:** Published definitions are live immediately—avoid breaking changes

3. **Create massdriver.yaml** with:
   - Params (with presets in `examples`)
   - Connections (dependencies from existing artifacts)
   - Artifacts (what this bundle produces)
   - UI ordering

4. **Create src/main.tf** with IaC code

5. **Create src/artifacts.tf** with `massdriver_artifact` resources

6. **Build and validate locally:**
   ```bash
   cd bundles/my-bundle
   mass bundle build
   cd src && tofu init && tofu validate
   ```

### Phase 3: Deploy Loop

**Initial Setup (once per package):**
```bash
# Publish development release
mass bundle publish --development

# Create package from bundle
mass pkg create <pkg-slug> --bundle <bundle-name>

# Set to development release channel (auto-deploys on publish)
mass pkg version <pkg-slug>@latest --release-channel development

# Configure package params
cat > /tmp/params.json << 'EOF'
{"param1": "value1", "param2": "value2"}
EOF
mass pkg cfg <pkg-slug> --params=/tmp/params.json

# Initial deploy
mass pkg deploy <pkg-slug> -m "Initial deployment for testing"
```

**Iteration Loop:**
```bash
# Make code changes
# ...

# Republish - package auto-upgrades and auto-deploys
mass bundle publish --development

# Check deployment logs for Checkov findings
mass logs <deployment-id> 2>&1 | grep -E "Check:|FAILED"

# Fix findings, republish, repeat until clean
```

**Testing Different Configurations:**
Create multiple packages to test different param combinations:
```bash
mass pkg create <pkg-slug>-variant2 --bundle <bundle-name>
mass pkg version <pkg-slug>-variant2@latest --release-channel development
mass pkg cfg <pkg-slug>-variant2 --params=/tmp/variant2-params.json
mass pkg deploy <pkg-slug>-variant2 -m "Testing alternate configuration"
```

**Config Changes (require manual deploy):**
```bash
mass pkg cfg <pkg-slug> --params=/tmp/updated-params.json
mass pkg deploy <pkg-slug> -m "Updated storage to 100GB, enabled deletion protection"
```

### Phase 4: Compliance Remediation

As Checkov findings emerge from deployments:

1. **Extract findings:**
   ```bash
   mass logs <deployment-id> 2>&1 | grep -E "Check:|FAILED"
   ```

2. **Triage by severity:**
   - **HIGH**: Fix by hardcoding secure defaults or adding params
   - **MEDIUM**: Fix if straightforward, document if deferred
   - **LOW/IGNORE**: Add to `src/.checkov.yml` with justification

3. **Fix and republish:**
   ```bash
   # Edit code to fix finding
   mass bundle publish --development
   # Package auto-deploys, check logs again
   ```

4. **For intentional skips**, update `src/.checkov.yml`:
   ```yaml
   skip-check:
     # LOW: Egress rule needed for AWS API calls
     - CKV_AWS_382
   ```

See [references/compliance.md](./references/compliance.md) for detailed remediation guidance.

### Phase 5: Finalization

**CRITICAL: Never publish stable without explicit human authorization.**

When the bundle is compliance-clean and tested:
1. Update README.md with changelog entry
2. Bump version in massdriver.yaml
3. Wait for human to authorize: `mass bundle publish`

---

## Build-Only Mode Workflow

For local development without deployments:

```bash
# 1. Create/edit bundle files
cd bundles/my-bundle

# 2. Build schemas
mass bundle build

# 3. Validate IaC
cd src && tofu init && tofu validate

# 4. Fix errors, repeat steps 2-3

# 5. When ready for deployment, switch to Full Mode
```

Build-only mode is useful for:
- Initial development before project/environment is ready
- Rapid iteration on Terraform code
- CI validation pipelines
- Working offline

---

## Core Concepts

**Bundle**: Reusable IaC module with declarative configuration (`massdriver.yaml` + `src/` code)

**Artifact Definition**: Schema contract defining data passed between bundles. Lives in `artifact-definitions/<name>/massdriver.yaml`. Supports:
- **Schema** → Generates UI form for manual artifact creation
- **Instructions** (`instructions/`) → Markdown walkthroughs for obtaining values
- **Exports** (`exports/`) → Downloadable files (e.g., kubeconfig)
- **Environment Defaults** (`ui.environmentDefaultGroup`) → Auto-assign to packages
- **Connection Orientation** (`ui.connectionOrientation`) → How connections appear in UI

**Platform**: An artifact definition for cloud credentials. Lives in `platforms/<name>/massdriver.yaml`. Identical structure to artifact definitions—separate directory for organization.

**Artifact**: Instance of an artifact definition containing actual data (credentials, connection strings). Created by bundles (`massdriver_artifact` resource) or users (UI form).

**Connection**: How bundles receive artifacts. Declared in `massdriver.yaml`, assigned in UI, flows as Terraform variable at deploy.

**Key Flow**: Edit `massdriver.yaml` → `mass bundle build` → `tofu validate` → `mass bundle publish --development`

---

## Bundle Design Philosophy

### Use-Case Oriented Bundles

Design bundles around developer use cases, not raw cloud APIs:

**Bad**: `aws-s3-bucket` (exposes every S3 option)
**Good**: `asset-storage` (for static assets), `data-lake-landing` (for data ingestion)

### The 80/20 Rule

A good bundle covers 80% of use cases. If a developer needs something outside that, they fork it. Resist over-generalization.

### Intentional Omission

Good bundles don't just encode defaults—they intentionally omit capabilities that don't belong:
- Asset storage shouldn't expose Glacier archival
- Logging buckets shouldn't expose public access
- Dev databases shouldn't offer Multi-AZ

### Developer-Focused Interface

Ask application questions, not infrastructure questions:
- **Bad**: "What instance class?" / "How many IOPS?"
- **Good**: "How much traffic do you expect?" / "What availability level?"

Presets (`params.examples`) anchor common choices in familiar language.

---

## Bundle Scoping and Resource Lifecycle

### The Lifecycle Principle

Ask these questions when deciding what belongs in a bundle:

1. **"If I delete this bundle, what should disappear?"** → All those resources belong together
2. **"Who owns this operationally?"** → Different owners = separate bundles
3. **"How often does this change?"** → Different change frequencies = separate bundles

### Lifecycle Tiers

**Foundational** (rarely changes): Networks, registries, DNS zones
**Stateful** (medium lifecycle): Databases, caches, queues
**Compute** (frequent changes): Applications, functions, jobs

### What Becomes a Connection

Resources that exist independently and are shared:
- VPC → network connection
- Kubernetes cluster → cluster connection
- Cloud credentials → authentication connection

### What Stays in the Bundle

Resources specific to and managed with the primary resource:
- Database bundle includes: DB instance, subnet group, security group, KMS key, parameter group
- All share the same lifecycle—delete one, delete all

### Scoping Decision Tree

```
Is this resource...
├─ Shared by multiple things? ────────────> Connection
├─ Created before and lives after? ───────> Connection
├─ Owned by a different team? ────────────> Connection
├─ Changes on very different schedule? ───> Connection
└─ Specific to and dies with primary? ────> Same bundle
```

---

## Schema Validation

Massdriver validates `massdriver.yaml` against:
- Bundles: https://api.massdriver.cloud/json-schemas/bundle.json
- Artifact Definitions: https://api.massdriver.cloud/json-schemas/artifact-definition.json

---

## Critical Rules

### 1. NEVER Edit Generated Files
Auto-generated by `mass bundle build` - changes will be overwritten:
- `schema-*.json`
- `_massdriver_variables.tf`

### 2. Namespace Collision Warning
Params and connections share Terraform variable namespace:
```yaml
# BAD - Both create var.network
params:
  properties:
    network:
connections:
  properties:
    network:
```

### 3. Artifact $ref Must Match Definition Name
```yaml
connections:
  properties:
    network:
      $ref: network  # References artifact-definitions/network/
```

### 4. artifacts.tf Must Match massdriver.yaml
```yaml
# massdriver.yaml
artifacts:
  properties:
    database:  # <-- field name
```
```hcl
# src/artifacts.tf
resource "massdriver_artifact" "database" {
  field = "database"  # Must match
}
```

### 5. Always Include massdriver Provider
```hcl
terraform {
  required_providers {
    massdriver = {
      source  = "massdriver-cloud/massdriver"
      version = "~> 1.3"
    }
  }
}
```

---

## File Responsibilities

| File | Purpose | Editable? |
|------|---------|-----------|
| `massdriver.yaml` | Source of truth - params, connections, artifacts, UI | Yes |
| `README.md` | Bundle documentation (displayed in UI) | Yes |
| `src/main.tf` | IaC code | Yes |
| `src/artifacts.tf` | massdriver_artifact resources | Yes |
| `src/.checkov.yml` | Checkov skip rules | Yes |
| `operator.md` | Runbook with mustache templating | Yes |
| `schema-*.json` | Generated schemas | **Never** |
| `_massdriver_variables.tf` | Generated variables | **Never** |

---

## Common Patterns

### Provider Blocks Use Credential Artifacts

```hcl
provider "aws" {
  region = var.region
  assume_role {
    role_arn    = var.aws_authentication.arn
    external_id = try(var.aws_authentication.external_id, null)
  }
  default_tags {
    tags = var.md_metadata.default_tags
  }
}
```

### Accessing Connection Data

```hcl
var.network.id
var.database.auth.hostname
[for s in var.network.subnets : s.id if s.type == "private"]
```

### Creating Artifacts

```hcl
resource "massdriver_artifact" "database" {
  field = "database"
  name  = "PostgreSQL ${var.md_metadata.name_prefix}"

  artifact = jsonencode({
    id = aws_rds_cluster.main.id
    auth = {
      hostname = aws_rds_cluster.main.endpoint
      port     = 5432
      database = var.database_name
      username = var.username
      password = random_password.main.result
    }
  })
}
```

### Param Presets

```yaml
params:
  examples:
    - __name: Development
      instance_type: "t3.small"
      storage_gb: 20
    - __name: Production
      instance_type: "r6g.large"
      storage_gb: 100
  properties:
    instance_type:
      type: string
    storage_gb:
      type: integer
```

### Dynamic Dropdowns from Connection Data

```yaml
params:
  properties:
    database_policy:
      type: string
      $md.enum:
        connection: database
        options: .policies
        value: .name
```

### Optional Connections

```yaml
connections:
  required:
    - network  # Required
  properties:
    network:
      $ref: network
    bucket:
      $ref: bucket  # Optional - not in required
```

```hcl
locals {
  has_bucket = var.bucket != null
}
```

---

## Checkov Security Configuration

Use `src/.checkov.yml` (inline comments don't work):

```yaml
skip-check:
  # S3 Bucket - cross-region replication not needed
  - CKV_AWS_144
  # Lambda - DLQ not required for simple API
  - CKV_AWS_116
```

Configure behavior in massdriver.yaml:
```yaml
steps:
  - path: src
    provisioner: opentofu:1.10
    config:
      checkov:
        enable: true
        halt_on_failure: '.params.md_metadata.default_tags["md-target"] == "production"'
```

### Skip vs. Halt Strategy

**Use skip-check for:** Architectural decisions that are intentionally permanent (e.g., using AWS-managed encryption instead of CMK). These checks provide no value.

**Let checks fail (rely on halt_on_failure) for:** User-configurable security settings (e.g., PITR, deletion protection). In dev, failures appear as warnings in logs—educating developers that their config won't pass in prod. In prod, halt_on_failure stops deployment.

Do NOT skip checks just because a param makes them optional. The warning visibility in dev is valuable feedback.

---

## Validation Checklist

Before publishing:
- [ ] `mass bundle build` succeeds
- [ ] No param/connection name conflicts
- [ ] Every artifact has matching `massdriver_artifact` resource
- [ ] `tofu init && tofu validate` passes
- [ ] Artifact JSON matches artifact definition schema
- [ ] Required providers include `massdriver-cloud/massdriver`

---

## Common Mistakes & Fixes

| Mistake | Fix |
|---------|-----|
| Coupled lifecycles (VPC in database bundle) | Use connections for foundational resources |
| Provider auth fails | Include ALL fields from credential artifact, use `try()` for optional fields |
| "variable not declared" | Run `mass bundle build` |
| Param/connection name collision | Rename one |
| artifacts.tf field mismatch | Ensure `field = "X"` matches `artifacts.properties.X` |
| Publishing stable during development | Use `--development` flag always until production-ready |
| Manual deploy after publish | Packages on development channel auto-deploy |
| Inline checkov:skip comments | Use `src/.checkov.yml` file instead |

---

## Commands Reference

```bash
# Discovery
mass bundle list              # List available bundles
mass def list                 # List artifact definitions
mass def get <name>           # Get artifact definition schema

# Build
mass bundle build             # Generate schemas + variables
tofu init && tofu validate    # Validate IaC

# Publish Bundles (NEVER without --development unless human authorized)
mass bundle publish --development

# Publish Artifact Definitions (careful: these are live immediately)
mass definition publish artifact-definitions/my-artifact/massdriver.yaml
mass definition publish platforms/my-cloud/massdriver.yaml

# Package Management
mass pkg create <slug> --bundle <bundle>
mass pkg version <slug>@latest --release-channel development
mass pkg cfg <slug> --params=/tmp/params.json
mass pkg deploy <slug> -m "Description of changes"

# Debugging
mass logs <deployment-id>
mass artifact get <artifact-name>

# Project/Environment
mass project create <slug> --name "<Name>"
mass env create <slug> --name "<Name>"
```

---

## See Also

- [PATTERNS.md](./PATTERNS.md) - Complete examples
- [references/alarms.md](./references/alarms.md) - Monitoring alarms
- [references/compliance.md](./references/compliance.md) - Checkov remediation
- [snippets/](./snippets/) - Copy-paste templates
