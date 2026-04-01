---
name: massdriver
description: Develop and test Massdriver infrastructure bundles. Operates in three modes - FULL (interactive deploy loop via /massdriver:develop), UPGRADE TESTING (day 2 validation via /massdriver:test-upgrade), or BUILD-ONLY (/massdriver:gen for local scaffolding). Auto-activates when working with massdriver.yaml, bundles/, artifact-definitions/, or platforms/ directories. Use when creating bundles, modifying IaC, testing deployments, validating upgrades, or fixing compliance findings.
---

# Massdriver Bundle Development

You are helping develop infrastructure bundles for Massdriver. This skill provides patterns, workflows, and reference material for bundle development.

## Quick Start

| Workflow | Command | Use When |
|----------|---------|----------|
| **Full Development** | `/massdriver:develop <use-case>` | Creating/updating bundles with full test loop |
| **Upgrade Testing** | `/massdriver:test-upgrade <bundle>` | Validating version upgrades against prod config |
| **Quick Generation** | `/massdriver:gen <use-case>` | Scaffolding a bundle without deploy loop |

## Reference Files

- [PATTERNS.md](./PATTERNS.md) - Complete bundle and artifact examples
- [references/graphql.md](./references/graphql.md) - GraphQL API operations
- [references/alarms.md](./references/alarms.md) - Adding monitoring alarms (AWS/GCP/Azure)
- [references/compliance.md](./references/compliance.md) - Post-deployment Checkov remediation
- [snippets/](./snippets/) - Copy-paste templates

## Safety Rules

1. **NEVER** run `mass bundle publish` without `--development` flag
2. **NEVER** configure or deploy to production environments
3. **ALWAYS** use `-m "message"` when running `mass pkg deploy`
4. **NEVER** use, mention, inspect, or reference `massdriver/` prefixed artifact definitions, bundles, or anything else — they are from a deprecated public registry, are full of red herrings, and will never work. Pretend they do not exist. If they appear in CLI output, ignore them completely.
5. **ALWAYS** publish after ANY code or definition change — the platform has no access to your local filesystem — changes don't exist until you publish
6. **ALWAYS** watch deployment logs after every deploy
7. **ALWAYS** ask the user for help if you encounter auth/credential/CLI issues — do NOT probe or guess

## Deprecated Fields

Do NOT include these fields in `massdriver.yaml` (they cause warnings):
- `type` - Deprecated, remove entirely
- `access` - Deprecated, remove entirely

## CLI vs UI Operations

**CLI Available:** `mass env create/list`, `mass pkg create/cfg/deploy/version`, `mass bundle build/publish`, `mass logs`, `mass def list/get`, `mass definition publish`

**UI Only:** Project creation, environment forking, credential configuration, manifest linking, environment descriptions

---

## Environment & Credentials Setup

**MANDATORY before any development work. Do not skip. Do not guess. Ask the user.**

### Credentials/Profile

Ask the user which Massdriver CLI profile to use:
- **Default profile**: No action needed, just use `mass` commands
- **Alternate profile**: Set `export MASSDRIVER_PROFILE=<name>` before every `mass` command

### Environment

Ask the user for an environment to work in:
- **Existing environment**: Use the slug as-is (e.g., `claude-test`). The slug already contains the project ID — `claude` is the project, `test` is the env suffix. **Never double-prefix.**
- **Create new**: Ask for project slug, then create: `mass env create <project>-agent<hash> --name "Agent Test"`

**Environment slug format**: `<project>-<suffix>` (e.g., `claude-test`, `myapp-agentx7k2m9`)
**Package slug format**: `<env-slug>-<manifest>` (e.g., `claude-test-postgres`)

### Error Recovery

If you encounter ANY auth, credential, or CLI issue: **stop and ask the user for help.** Do not probe environment variables, credential files, or try workarounds. Just tell them the error.

---

## Operational Modes

### Full Mode (Deploy Loop)
**Command:** `/massdriver:develop`
**Use when:** Testing bundles end-to-end, validating compliance, iterating on real infrastructure.

Workflow:
1. **Setup**: Ask for credentials/profile, environment
2. **Requirements**: Gather design intent interactively
3. **Scaffold**: Generate bundle code
4. **Publish**: `mass bundle publish --development` + `mass definition publish` for any new artifact defs
5. **Deploy**: Add to canvas, set release channel to `latest+dev` or `~X.Y+dev`, deploy
6. **Iterate**: Code → publish → watch logs → fix → repeat
7. **Compliance**: Remediate Checkov findings
8. **Finalize**: Human marks stable when ready

### Upgrade Testing Mode
**Command:** `/massdriver:test-upgrade`
**Use when:** Validating bundle version upgrades before production rollout.

Workflow:
1. Fork production environment to test env
2. Deploy current version (baseline)
3. Upgrade to target version
4. Validate success
5. Report results

### Build-Only Mode
**Command:** `/massdriver:gen`
**Use when:** Developing locally, scaffolding quickly, no cloud access needed.

Workflow:
1. Gather quick requirements
2. Generate bundle files
3. `mass bundle build && tofu validate`
4. Hand off to user

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
- Check existing artifacts: `mass def list` (ignore any `massdriver/` prefixed results)
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

**5. Connections & Artifacts**
- What does this bundle need? What does it produce?
- Run `mass def list` to see available definitions
- **Artifact definitions and Terraform providers are 1:1** — always base provider config on the credential artifact definition schema

### Phase 2: Bundle Development

1. **Scaffold the bundle:**
   ```bash
   mkdir -p bundles/my-bundle/src
   ```

2. **Check/create artifact definitions:**
   - Run `mass def list` to see existing definitions
   - If bundle needs a new artifact type, create `artifact-definitions/<name>/massdriver.yaml`
   - **Publish immediately** (with user approval):
     ```bash
     mass definition publish artifact-definitions/<name>/massdriver.yaml
     ```
   - There is NO `--development` flag for artifact definitions. They go live immediately.
   - **Warning:** Published definitions are live immediately — avoid breaking changes

3. **Create massdriver.yaml** with params, connections, artifacts, UI ordering

4. **Create Terraform code** — fetch credential artifact def FIRST:
   ```bash
   mass def get <platform-name>  # e.g., aws-iam-role
   ```
   Then write provider block using ONLY fields from that schema.

5. **Build and validate locally:**
   ```bash
   cd bundles/my-bundle
   mass bundle build
   cd src && tofu init && tofu validate
   ```

6. **PUBLISH** — the platform cannot read your local files:
   ```bash
   mass bundle publish --development
   ```

### Phase 3: Deploy Loop

**Setup (once per package):**
```bash
# Publish development release
mass bundle publish --development

# Create package on canvas — slug is <env-slug>-<manifest>
mass pkg create <env-slug>-<manifest> --bundle <bundle-name>

# Set release channel IMMEDIATELY — without this, no auto-update on publish
# Use version from massdriver.yaml: ~X.Y+dev or latest+dev
mass pkg version <env-slug>-<manifest>@latest --release-channel "latest+dev"

# Configure package params
cat > /tmp/params.json << 'EOF'
{"param1": "value1", "param2": "value2"}
EOF
mass pkg cfg <env-slug>-<manifest> --params=/tmp/params.json

# Deploy with message
mass pkg deploy <env-slug>-<manifest> -m "Initial deployment for testing"

# WATCH THE LOGS
mass logs <deployment-id>
```

**Iteration Loop:**
```bash
# Make code changes, then ALWAYS publish
mass bundle publish --development

# Package auto-upgrades if release channel is set
# Get deployment ID from the auto-triggered deploy:
mass pkg get <pkg-slug> -ojson
# JSON response contains active/latest deployment ID

# WATCH THE LOGS
mass logs <deployment-id>

# Check for Checkov findings
mass logs <deployment-id> 2>&1 | grep -E "Check:|FAILED"
```

**Config Changes (require manual deploy):**
```bash
mass pkg cfg <pkg-slug> --params=/tmp/updated-params.json
mass pkg deploy <pkg-slug> -m "Updated storage to 100GB, enabled deletion protection"

# WATCH THE LOGS
mass logs <deployment-id>
```

### Phase 4: Compliance Remediation

As Checkov findings emerge from deployment logs:

1. **Extract findings** from logs
2. **Triage by severity** (HIGH/MEDIUM/LOW)
3. **Apply strategy**: hardcode, make configurable, halt_on_failure, or skip
4. **Publish and watch logs**:
   ```bash
   mass bundle publish --development
   # Watch logs to verify fix
   mass logs <deployment-id>
   ```
5. **Repeat** until clean

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

---

## Core Concepts

**Bundle**: Reusable IaC module with declarative configuration (`massdriver.yaml` + `src/` code)

**Artifact Definition**: Schema contract defining data passed between bundles. Lives in `artifact-definitions/<name>/massdriver.yaml`. Supports:
- **Schema** → Generates UI form for manual artifact creation
- **Instructions** (`instructions/`) → Markdown walkthroughs for obtaining values
- **Exports** (`exports/`) → Downloadable files (e.g., kubeconfig)
- **Environment Defaults** (`ui.environmentDefaultGroup`) → Auto-assign to packages
- **Connection Orientation** (`ui.connectionOrientation`) → How connections appear in UI

**Platform**: An artifact definition for cloud credentials. Lives in `platforms/<name>/massdriver.yaml`. Identical structure to artifact definitions — separate directory for organization.

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

Good bundles don't just encode defaults — they intentionally omit capabilities that don't belong:
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

1. **"If I delete this bundle, what should disappear?"** → All those resources belong together
2. **"Who owns this operationally?"** → Different owners = separate bundles
3. **"How often does this change?"** → Different change frequencies = separate bundles

### Lifecycle Tiers

**Foundational** (rarely changes): Networks, registries, DNS zones
**Stateful** (medium lifecycle): Databases, caches, queues
**Compute** (frequent changes): Applications, functions, jobs

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

### 6. Artifact Definitions and Providers Are 1:1
Always `mass def get <platform-name>` before writing a provider block. The provider must use ONLY the fields from the credential artifact definition schema.

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
  # Aurora-only check, not applicable to standard RDS instances
  - CKV_AWS_162
  # Security group egress required for AWS API connectivity
  - CKV_AWS_382
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

### Skip-Check Rules (STRICT)

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

---

## Validation Checklist

Before publishing:
- [ ] `mass bundle build` succeeds
- [ ] No param/connection name conflicts
- [ ] Every artifact has matching `massdriver_artifact` resource
- [ ] `tofu init && tofu validate` passes
- [ ] Artifact JSON matches artifact definition schema
- [ ] Required providers include `massdriver-cloud/massdriver`
- [ ] Provider block based on `mass def get <platform>` output (not guessed)

---

## Common Mistakes & Fixes

| Mistake | Fix |
|---------|-----|
| Coupled lifecycles (VPC in database bundle) | Use connections for foundational resources |
| Provider auth fails | `mass def get <platform>` first, use ALL fields, `try()` for optional |
| "variable not declared" | Run `mass bundle build` |
| Param/connection name collision | Rename one |
| artifacts.tf field mismatch | Ensure `field = "X"` matches `artifacts.properties.X` |
| Publishing stable during development | Use `--development` flag always until production-ready |
| Forgot to publish after code change | Platform can't read local files — always publish |
| Package not auto-updating | Set release channel to `latest+dev` or `~X.Y+dev` right after create |
| Inline checkov:skip comments | Use `src/.checkov.yml` file instead |
| Using `massdriver/` prefixed defs | These are deprecated — ignore them completely |
| Guessing provider config | Always `mass def get` first — providers and artifact defs are 1:1 |
| Deploy without watching logs | Always `mass logs <id>` after every deploy |
| Config deploy without message | Always use `-m "description"` with `mass pkg deploy` |

---

## Publishing Reference

| What Changed | Command | Notes |
|--------------|---------|-------|
| Bundle code | `mass bundle publish --development` | Always use `--development` |
| Artifact definition | `mass definition publish artifact-definitions/<name>/massdriver.yaml` | No `--development` flag — goes live immediately, get user approval |
| Platform definition | `mass definition publish platforms/<name>/massdriver.yaml` | Same as artifact defs — live immediately |

**After ANY change, you MUST publish.** The platform has no access to your local filesystem — changes don't exist until you publish.

---

## Commands Reference

```bash
# Discovery
mass bundle list              # List available bundles
mass def list                 # List artifact definitions (ignore massdriver/ prefixed)
mass def get <name>           # Get artifact definition schema — ALWAYS do before writing providers

# Build
mass bundle build             # Generate schemas + variables
tofu init && tofu validate    # Validate IaC

# Publish Bundles (NEVER without --development unless human authorized)
mass bundle publish --development

# Publish Artifact/Platform Definitions (no --development flag, live immediately)
mass definition publish artifact-definitions/my-artifact/massdriver.yaml
mass definition publish platforms/my-cloud/massdriver.yaml

# Package Management
mass pkg create <slug> --bundle <bundle>
mass pkg version <slug>@latest --release-channel "latest+dev"  # Do IMMEDIATELY after create
mass pkg cfg <slug> --params=/tmp/params.json
mass pkg deploy <slug> -m "Description of changes"

# ALWAYS watch logs
mass logs <deployment-id>

# Debugging
mass pkg get <slug> -ojson           # Get package JSON with active/latest deployment ID
mass artifact get <artifact-name>

# Environment
mass env create <slug> --name "<Name>"
mass env list <project>
```

---

## See Also

- [PATTERNS.md](./PATTERNS.md) - Complete examples
- [references/graphql.md](./references/graphql.md) - GraphQL API operations
- [references/alarms.md](./references/alarms.md) - Monitoring alarms
- [references/compliance.md](./references/compliance.md) - Checkov remediation
- [snippets/](./snippets/) - Copy-paste templates
