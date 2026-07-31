---
name: massdriver
description: Develop and test Massdriver v2 infrastructure bundles. Operates in three modes - FULL (interactive deploy loop via /massdriver:develop), UPGRADE TESTING (day 2 validation via /massdriver:test-upgrade), or BUILD-ONLY (/massdriver:gen for local scaffolding). Auto-activates when working with massdriver.yaml, bundles/, resource-type/ (or legacy artifact-definitions/), platforms/, or projects/ directories. Use when creating bundles, modifying IaC, testing deployments, validating upgrades, or fixing compliance findings.
---

# Massdriver Bundle Development (v2)

You are helping develop infrastructure bundles for Massdriver v2. This skill provides patterns, workflows, and reference material for bundle development against the v2 platform.

**Tooling hierarchy — MCP first.** Every control-plane operation (projects, environments, components, instances, deployments, resources) is a tool on the `massdriver` MCP server — the server's tool list and schemas are the reference; don't guess arguments, read them. The `mass` CLI is used ONLY for filesystem-bound work the MCP server can't touch (see CLI Reference at the bottom). The UI is only for first-time credential/secret bootstrapping and visual canvas inspection — hand the user a deep link with `get_url`. GraphQL is optional, for multi-entity queries only ([references/graphql.md](./references/graphql.md)).

## v2 Mental Model (read first)

Massdriver v2 separates **design time** from **deploy time**:

- **Project** — owns a **blueprint**: a graph of `components` connected by `links`. The blueprint is the architecture.
- **Component** — a slot in the blueprint backed by a bundle (the IaC). Add a component once at the project level — every environment gets it automatically.
- **Link** — a design-time wire from one component's output field to another component's input field. Becomes a connection at deploy time.
- **Environment** — a deployment context (e.g. `prod`, `staging`, `agentx7k2`). Environments materialize the blueprint into instances.
- **Instance** — a deployed component in a specific environment. Slug is `<project>-<env>-<component>` (e.g. `ecomm-prod-db`).
- **Resource** — the runtime output of an instance, conforming to a **resource type** (the schema contract). Bundles author "artifacts" in `massdriver.yaml`; those become resources at deploy time.

Components are added exactly once, at the project level (`add_component`) — never per environment. Every environment automatically gets an instance for every component.

## Quick Start

| Workflow | Command | Use When |
|----------|---------|----------|
| **Full Development** | `/massdriver:develop <use-case>` | Creating/updating bundles with full test loop |
| **Upgrade Testing** | `/massdriver:test-upgrade <bundle>` | Validating version upgrades against prod config |
| **Quick Generation** | `/massdriver:gen <use-case>` | Scaffolding a bundle without deploy loop |

## Reference Files

- [PATTERNS.md](./PATTERNS.md) - Complete bundle and artifact examples
- [references/graphql.md](./references/graphql.md) - GraphQL multi-entity queries
- [references/alarms.md](./references/alarms.md) - Adding monitoring alarms (AWS/GCP/Azure)
- [references/compliance.md](./references/compliance.md) - Post-deployment Checkov remediation
- [snippets/](./snippets/) - Copy-paste templates

## Safety Rules

1. **NEVER** run `mass bundle publish` without `--development` (`-d`) flag
2. **NEVER** configure or deploy to production environments
3. **ALWAYS** pass a `message` when creating deployments (`create_deployment`, `propose_deployment`)
4. **NEVER** use, mention, inspect, or reference `massdriver/` prefixed resource types, bundles, or anything else — they are from a deprecated public registry, are full of red herrings, and will never work. Pretend they do not exist. If they appear in tool output, ignore them completely.
5. **ALWAYS** publish after ANY code or definition change — the platform has no access to your local filesystem — changes don't exist until you publish
6. **ALWAYS** watch deployment logs after every deploy (`get_deployment_logs` with `follow: true`)
7. **ALWAYS** ask the user for help if you encounter auth/credential/tooling issues — do NOT probe or guess
8. **NEVER** call `approve_deployment` — approving proposed deployments (including rollbacks) is a human authorization step. The safety hook blocks it.

## Deprecated `massdriver.yaml` Fields

Do NOT include these fields (they cause linter warnings):
- `type` — Deprecated, remove entirely
- `access` — Deprecated, remove entirely

## Tool Boundaries

**MCP:** every control-plane operation is an MCP tool — the server's tool list and schemas are the reference; don't guess arguments, read them.

**CLI only (filesystem-bound — the MCP server cannot touch local files):**
- Bundle lifecycle: `mass bundle build|lint|new|publish|pull|import|template`
- Resource types: `mass resource-type publish|get|list`
- Local dev: `mass server`, `mass schema validate|dereference`, `mass whoami`

**UI Only:** first-time credential/secret bootstrapping and visual canvas inspection. Use `get_url` to hand the user a deep link.

**GraphQL:** nothing requires it. Use it only when one query spanning several entities beats a chain of tool calls. See [references/graphql.md](./references/graphql.md).

---

## Environment & Credentials Setup

**MANDATORY before any development work. Do not skip. Do not guess. Ask the user.**

### Credentials/Profile

- **MCP auth**: verify connectivity with `get_viewer` — it returns the authenticated identity. If it fails, stop, report the exact error, and ask the user to fix their MCP setup.
- **CLI profile** (needed for publish/build steps): ask which profile to use. Default profile needs no action; for an alternate profile set `export MASSDRIVER_PROFILE=<name>` before every `mass` command.

### Project & Environment

In v2 you'll likely need both a **project** and an **environment** before deploying anything:

- **Existing project + environment**: ask for the slugs and use them as-is. Instance slugs are `<project>-<env>-<component>`. Don't double-prefix.
- **Create new** (MCP): `create_project` (`id`, `name`), then `create_environment` (`project_id`, `id` = env suffix, `name`).
- **Clone a blueprint**: `clone_project` duplicates components + wiring into a new project (no environments copied).
- **Fork from prod**: `fork_environment` — copies the parent's component configuration into the new environment, with opt-in toggles for secrets, remote references, and environment defaults.

**Slug format reminders:**
- Project slug, env suffix, component id: max 20 chars, lowercase alphanumeric only.
- Instance slug = `<project>-<env>-<component>` (e.g. `ecomm-prod-db`).
- `create_environment` takes the project via `project_id` and just the env suffix as `id`; every other tool takes the FULL `<project>-<env>` environment identifier.
- Resource slug = `<project>-<env>-<component>.<artifact-field>` (e.g. `ecomm-prod-db.database`).

### Error Recovery

If you encounter ANY auth, credential, CLI, or MCP connectivity issue: **stop and ask the user for help.** Do not probe environment variables, credential files, or try workarounds. Just tell them the error.

---

## Operational Modes

### Full Mode (Deploy Loop)
**Command:** `/massdriver:develop`
**Use when:** Testing bundles end-to-end, validating compliance, iterating on real infrastructure.

Workflow:
1. **Setup**: Verify MCP auth (`get_viewer`), ask for CLI profile, project, environment
2. **Requirements**: Gather design intent interactively
3. **Scaffold**: Generate bundle code
4. **Publish** (CLI): `mass bundle publish --development` (and `mass resource-type publish` for any new resource types)
5. **Add to blueprint** (MCP): `add_component` with `project_id`, `bundle_name`, `id`, `name` (once per project)
6. **Pin development channel** (MCP): `update_instance` with version `latest+dev` — the `+dev` suffix on the version constraint opts into development releases
7. **Deploy** (MCP): `create_deployment` (action `PROVISION`, params, message) then `get_deployment_logs` with `follow: true`
8. **Iterate**: Code → publish (CLI) → `create_deployment` again → fix → repeat
9. **Compliance**: Remediate Checkov findings
10. **Finalize**: Human marks stable when ready

### Upgrade Testing Mode
**Command:** `/massdriver:test-upgrade`
**Use when:** Validating bundle version upgrades before production rollout.

Workflow:
1. Fork production environment to a test env (`fork_environment` — copies component config; opt into secrets/refs/defaults)
2. Adjust any instances that shouldn't mirror prod exactly (`copy_instance` with `overrides`, e.g. low-scale dependencies)
3. Verify the mirror with `compare_environments`
4. Deploy current version as baseline (`create_deployment` + `get_deployment_logs follow:true`)
5. Pin target version (`update_instance`) → deploy upgrade
6. Validate success; audit what changed with `compare_deployments`
7. Report results (with `rollback_deployment` as the escape hatch if the upgrade regresses)
8. Tear down with `decommission_environment`, optionally `delete_environment`

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
- Check existing bundles: `list_oci_repos` with `artifact_type: BUNDLE` (MCP)
- Check existing resource types: `mass resource-type list` (CLI — ignore any `massdriver/` prefixed results)
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
- Run `mass resource-type list` (CLI) to see available resource type definitions
- **Resource types and Terraform providers are 1:1** — always base provider config on the credential resource type's schema

### Phase 2: Bundle Development

1. **Scaffold the bundle:**
   ```bash
   mkdir -p bundles/my-bundle/src
   # or use the template generator:
   mass bundle new -n my-bundle -t opentofu
   ```

2. **Check/create resource types:**
   - Run `mass resource-type list` to see existing resource types
   - If the bundle needs a new resource type, create `resource-type/<name>/massdriver.yaml` (or `platforms/<name>/massdriver.yaml` for credential types — purely organizational)
   - **Publish immediately** (with user approval):
     ```bash
     mass resource-type publish resource-type/<name>/massdriver.yaml
     ```
   - Resource types go live immediately — there is NO `--development` flag.
   - **Warning:** Published resource types are live immediately — avoid breaking changes.

3. **Create massdriver.yaml** with params, connections, artifacts, UI ordering. Naming note: the bundle YAML section key is `artifacts:`, but what those publish (via `massdriver_resource` HCL resources) surface at deploy time as runtime "resources".

4. **Create Terraform code** — fetch the credential resource type FIRST:
   ```bash
   mass resource-type get <platform-name>  # e.g. aws-iam-role
   ```
   Then write the provider block using ONLY fields from that schema.

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

### Phase 3: Add to Project Blueprint

Components live at the **project** level in v2. Once added, every environment auto-gets an instance. Use MCP:

- `add_component` — one-time per (project, bundle) pair
- `link_components` — wire one component's output field to another's input field (component IDs are `<project>-<comp>`)

The component `id` is the final segment of every instance slug — keep it short (max 20 chars, lowercase alphanumeric).

### Phase 4: Deploy Loop

**Initial deploy in a target environment:**

1. **Pin the development channel** (MCP) so the instance picks up `--development` publishes: `update_instance` with version `latest+dev`. Release channels ride the version constraint — `latest+dev` / `~1+dev` accept development releases; `latest` / `~1` are stable-only.
2. **Deploy** (MCP): `create_deployment` (action `PROVISION`) with your preset params and a descriptive message
3. **Watch logs** (MCP): `get_deployment_logs` with `follow: true` — blocks until the deployment reaches a terminal status and returns the final status plus complete logs. Long deploys can outlast the default wait; raise `timeout_seconds` and re-call if still running.

**Iteration Loop:**

1. Make code changes, then ALWAYS publish (CLI): `mass bundle publish --development`
2. Redeploy (MCP), three flavors:
   - **Reuse last config** (just pick up the new release): `create_deployment` with `action: PROVISION` and NO `params`, plus a `message`
   - **Surgical edit**: `get_instance` to read the current `params`, modify the specific fields, then `create_deployment` with the full updated params
   - **Replace config**: `create_deployment` with the complete new `params` object
3. Check Checkov findings in the `get_deployment_logs` output (look for `Check:` / `FAILED` lines)

**Key ergonomic wins to remember:**
- `create_deployment` without `params` reuses the instance's saved config — handy after a publish to roll the new release without re-stating params.
- `get_deployment_logs follow:true` rolls deploy-watching into one call — no polling loop.
- `compare_deployments` shows exactly what a deploy changed (bundle version + leaf-level param diff).
- `plan_deployment` re-runs a dry-run PLAN from any existing deployment's params without touching anything.

### Phase 5: Compliance Remediation

As Checkov findings emerge from deployment logs:

1. **Extract findings** from logs
2. **Triage by severity** (HIGH/MEDIUM/LOW)
3. **Apply strategy**: hardcode, make configurable, halt_on_failure, or skip
4. **Publish and redeploy**: `mass bundle publish --development` (CLI), then `create_deployment` (action `PROVISION`, no params, message `"Fix CKV_AWS_xxx"`) and `get_deployment_logs follow:true` (MCP)
5. **Repeat** until clean

See [references/compliance.md](./references/compliance.md) for detailed remediation guidance.

### Phase 6: Finalization

**CRITICAL: Never publish stable without explicit human authorization.**

When the bundle is compliance-clean and tested:
1. Update README.md with changelog entry
2. Bump version in massdriver.yaml
3. Wait for human to authorize: `mass bundle publish` (no `--development`)

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

# 4. Optionally lint
cd .. && mass bundle lint

# 5. Optionally run the local dev server for interactive exploration
mass server -p 8080 --browser

# 6. When ready for deployment, switch to Full Mode
```

---

## Core Concepts

**Bundle**: Reusable IaC module with declarative configuration (`massdriver.yaml` + `src/` code). Published to an OCI repository.

**Resource Type**: Schema contract defining data passed between bundles. Lives in `resource-type/<name>/massdriver.yaml`. Supports:
- **Schema** → Generates UI form for manual resource creation
- **Instructions** (`instructions/`) → Markdown walkthroughs for obtaining values
- **Exports** (`exports/`) → Downloadable files (e.g., kubeconfig)
- **Environment Defaults** (`ui.environmentDefaultGroup`) → Auto-assign to instances
- **Connection Orientation** (`ui.connectionOrientation`) → How connections appear in UI

**Platform**: A resource type for cloud credentials. Lives in `platforms/<name>/massdriver.yaml`. Identical structure to other resource types — separate directory for organization only.

**Resource**: An instance of a resource type containing actual data (credentials, connection strings). Created by bundles via the `massdriver_resource` Terraform resource, or by users (UI form / `create_resource` MCP tool).

**Connection**: How instances receive resources at deploy time. Authored in `massdriver.yaml`, wired in the project blueprint via `link_components`, materialized as a connection in each environment, flows to Terraform as a variable at deploy. Overridable per instance with `set_remote_reference` (bind a slot to a resource from another project or an imported resource).

**Component**: A slot in a project's blueprint backed by a bundle. Added once via `add_component`. Every environment auto-instantiates every component.

**Instance**: A deployed component in a specific environment. Slug is `<project>-<env>-<component>`. Configured + deployed via `create_deployment`.

**Key Flow**: Edit `massdriver.yaml` → `mass bundle build` → `tofu validate` → `mass bundle publish --development` (CLI) → `create_deployment` + `get_deployment_logs follow:true` (MCP)

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
- Resource Types: https://api.massdriver.cloud/json-schemas/artifact-definition.json (the URL still uses the legacy name; the document itself is the v2 schema)

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

### 3. Artifact $ref Must Match Resource Type Name
```yaml
connections:
  properties:
    network:
      $ref: network  # References resource-type/network/
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
resource "massdriver_resource" "database" {
  field = "database"  # Must match
}
```

### 5. Always Include massdriver Provider
```hcl
terraform {
  required_providers {
    massdriver = {
      source  = "massdriver-cloud/massdriver"
      version = "~> 2.0"
    }
  }
}
```

### 6. Resource Types and Providers Are 1:1
Always `mass resource-type get <platform-name>` before writing a provider block. The provider must use ONLY the fields from the credential resource type's schema.

---

## File Responsibilities

| File | Purpose | Editable? |
|------|---------|-----------|
| `massdriver.yaml` | Source of truth - params, connections, artifacts, UI | Yes |
| `README.md` | Bundle documentation (displayed in UI) | Yes |
| `src/main.tf` | IaC code | Yes |
| `src/artifacts.tf` | massdriver_resource resources | Yes |
| `src/.checkov.yml` | Checkov skip rules | Yes |
| `operator.md` | Runbook with mustache templating | Yes |
| `schema-*.json` | Generated schemas | **Never** |
| `_massdriver_variables.tf` | Generated variables | **Never** |

---

## Common Patterns

### Provider Blocks Use Credential Resources

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
resource "massdriver_resource" "database" {
  field = "database"
  name  = "PostgreSQL ${var.md_metadata.name_prefix}"

  resource = jsonencode({
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
    provisioner: opentofu
    config:
      checkov:
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
- [ ] `mass bundle lint` is clean (or run `mass bundle publish --development --fail-warnings`)
- [ ] No param/connection name conflicts
- [ ] Every artifact has matching `massdriver_resource` resource
- [ ] `tofu init && tofu validate` passes
- [ ] Artifact JSON matches the resource type's schema
- [ ] Required providers include `massdriver-cloud/massdriver`
- [ ] Provider block based on `mass resource-type get <platform>` output (not guessed)

---

## Common Mistakes & Fixes

| Mistake | Fix |
|---------|-----|
| Coupled lifecycles (VPC in database bundle) | Use connections for foundational resources |
| Provider auth fails | `mass resource-type get <platform>` first, use ALL fields, `try()` for optional |
| "variable not declared" | Run `mass bundle build` |
| Param/connection name collision | Rename one |
| artifacts.tf field mismatch | Ensure `field = "X"` matches `artifacts.properties.X` |
| Publishing stable during development | Use `--development` flag always until production-ready |
| Forgot to publish after code change | Platform can't read local files — always publish |
| Instance not picking up new release after publish | Pin the development channel: `update_instance` with version `latest+dev` |
| Assumed a release-channel flag or enum | Channels ride the version constraint: `latest+dev` / `~1+dev` for development, `latest` / `~1` for stable |
| Tried `mass pkg create` / `mass component add` for deploys | `add_component` (MCP) once at the project level |
| Tried `mass pkg cfg` to set params | Params travel with each `create_deployment` call |
| Used `mass logs` or CLI deploy commands | `create_deployment` + `get_deployment_logs` (`follow: true`) via MCP |
| Deployed via CLI when MCP is available | Control-plane ops go through MCP tools; CLI is for filesystem work only |
| Called `approve_deployment` | Approval is human-only — the safety hook blocks it. Ask the user to approve in the UI |
| Inline checkov:skip comments | Use `src/.checkov.yml` file instead |
| Using `massdriver/` prefixed defs | These are deprecated — ignore them completely |
| Guessing provider config | Always `mass resource-type get` first — providers and resource types are 1:1 |
| Deploy without watching logs | Always follow with `get_deployment_logs` (`follow: true`) |
| Deployment without message | Always pass `message` to `create_deployment` |

---

## Publishing Reference

| What Changed | Command | Notes |
|--------------|---------|-------|
| Bundle code | `mass bundle publish --development` | Always use `--development` (or `-d`) |
| Resource type | `mass resource-type publish resource-type/<name>/massdriver.yaml` | Goes live immediately, no `--development` flag, get user approval |
| Platform definition | `mass resource-type publish platforms/<name>/massdriver.yaml` | Same as resource types — live immediately |

**After ANY change, you MUST publish.** The platform has no access to your local filesystem — changes don't exist until you publish.

After publishing a new bundle release, instances on the `development` release channel auto-resolve to it. To force a redeploy of the new release without changing config, call `create_deployment` with `action: PROVISION`, no `params`, and a message like `"Pick up new release"`.

---

## CLI Reference

```bash
# Resource types
mass resource-type list                  # Ignore massdriver/ prefixed
mass resource-type get <name>            # ALWAYS do before writing providers

# Build / Lint / Local
mass bundle build                        # Generate schemas + variables
mass bundle lint                         # Check massdriver.yaml for errors
mass bundle new -n my-bundle -t opentofu # Scaffold from a template
mass bundle pull <name>                  # Pull a published bundle to disk
mass server                              # Local bundle dev server
mass schema validate|dereference         # Schema tooling
tofu init && tofu validate               # Validate IaC

# Publish (NEVER stable without explicit human authorization)
mass bundle publish --development
mass resource-type publish resource-type/my-type/massdriver.yaml
mass resource-type publish platforms/my-cloud/massdriver.yaml

# Auth / introspection
mass whoami
mass version
```

---

## See Also

- [PATTERNS.md](./PATTERNS.md) - Complete examples
- [references/graphql.md](./references/graphql.md) - GraphQL multi-entity queries
- [references/alarms.md](./references/alarms.md) - Monitoring alarms
- [references/compliance.md](./references/compliance.md) - Checkov remediation
- [snippets/](./snippets/) - Copy-paste templates
