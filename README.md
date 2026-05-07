# Massdriver Plugin for Claude Code (v2)

Build infrastructure bundles for [Massdriver](https://massdriver.cloud) v2 — the internal developer platform that turns infrastructure-as-code into reusable, self-service components with built-in guardrails.

This plugin requires the **v2 Massdriver CLI** (`mass`) and targets the **v2 GraphQL API**. It is not compatible with v1.

## Installation

```bash
# Add the marketplace
/plugin marketplace add massdriver-cloud/claude-plugins

# Install the plugin
/plugin install massdriver@massdriver-cloud-claude-plugins
```

## Commands

### `/massdriver:develop` - Full Bundle Development

Interactive workflow for creating and testing bundles with deploy loop and compliance remediation.

```
/massdriver:develop PostgreSQL database for application backends with dev/staging/prod presets
```

```
/massdriver:develop S3 bucket for static asset storage with CloudFront CDN
```

**What it does:**
1. Gathers your design intent (UX, constraints, connections)
2. Scaffolds the bundle with best practices
3. Sets up project + ephemeral test environment (`<project>-agent<SUFFIX>`)
4. Adds the bundle as a component in the project's blueprint (`mass component add`)
5. Pins the test instance to the `development` release channel
6. Runs deploy loop: `mass instance deploy --params=... --follow`, then surgical `--patch` edits
7. Remediates compliance findings automatically
8. Journals results in environment description (`mass environment update --description`)

### `/massdriver:test-upgrade` - Day 2 Upgrade Testing

Validate bundle version upgrades by forking the production environment and copying its instance config to a test environment.

```
/massdriver:test-upgrade api-prod-database 1.3.0
```

Instance slugs follow the v2 format `{project}-{environment}-{component}`.

**What it does:**
1. Forks the source instance's environment via the `forkEnvironment` GraphQL mutation (no CLI verb yet — UI or GraphQL)
2. Seeds the forked instance(s) using `copyInstance` (you can override fields, opt into copying secrets/remote refs)
3. Deploys the current version as a baseline
4. Bumps version with `mass instance version <slug>@<target>` and redeploys
5. Reports success/failure with recommendations

### `/massdriver:gen` - Quick Scaffolding

Generate a bundle without the deploy loop.

```
/massdriver:gen RDS MySQL for OLTP workloads
```

## What's New in v2

If you're coming from this plugin's v3.x (which targeted Massdriver v1), the major shifts:

- **Project blueprints**: Bundles are added to a project's blueprint once via `mass component add`. Every environment auto-gets an instance.
- **`mass instance deploy`**: One command for config + deploy + log streaming (`--params`, `--patch`, `--follow`). Replaces `mass pkg cfg` + `mass pkg deploy` + `mass logs`.
- **CLI-first lifecycle**: Project + environment creation, blueprint composition (`mass component add|link`), and the dev server (`mass server`) are all CLI now.
- **Lowercase release channels**: `--release-channel development` (or `stable`). The old `latest+dev` / `~X.Y+dev` strings are gone.
- **Renames**: `pkg` → `instance`, `def` → `resource-type`, `artifact` → `resource`, `env` → `environment`, `mass logs` → `mass deployment logs`. Old verbs work as aliases for now but new code should use the new names.

## What This Plugin Does

This plugin helps platform engineers create and test Massdriver v2 bundles — reusable IaC modules that package OpenTofu, Terraform, or Helm with input schemas, resource type contracts, and operational policies.

**Capabilities:**
- **Interactive development**: Full deploy loop with compliance remediation
- **Upgrade testing**: Validate version upgrades against production configs (via fork + copyInstance)
- **Safety guardrails**: Blocks non-development publishes and production-targeting writes
- **Compliance automation**: Iterates until Checkov findings are resolved
- **GraphQL v2 integration**: Reference for operations not yet in the CLI (forkEnvironment, copyInstance, deployment approval flow, instance secrets)

## When It Activates

The plugin auto-activates when:
- Working in `bundles/`, `resource-type/` (or legacy `artifact-definitions/`), `platforms/`, or `projects/` directories
- Editing `massdriver.yaml` files
- Asking about bundles, resource types, components, instances, connections, or Massdriver patterns
- Requesting to create, develop, or test bundles

## Plugin Contents

```
claude-plugins/
├── .claude-plugin/
│   └── marketplace.json
└── massdriver/
    ├── .claude-plugin/
    │   └── plugin.json
    ├── agents/
    │   ├── bundle-dev.md           # Full development workflow (v2)
    │   └── upgrade-tester.md       # Day 2 upgrade testing (v2)
    ├── commands/
    │   ├── develop.md              # /massdriver:develop
    │   ├── test-upgrade.md         # /massdriver:test-upgrade
    │   └── gen.md                  # /massdriver:gen
    ├── hooks/
    │   └── hooks.json              # Safety guardrails (v2 command surface)
    ├── templates/
    │   └── massdriver.local.md     # Settings template
    └── skills/
        └── massdriver/
            ├── SKILL.md            # Core knowledge (v2 mental model + workflows)
            ├── PATTERNS.md         # Bundle and resource type examples
            └── references/
                ├── graphql.md      # GraphQL v2 API operations
                ├── alarms.md       # AWS/GCP/Azure monitoring
                └── compliance.md   # Checkov remediation
```

## Safety Guardrails

The plugin includes automatic safety hooks that **hard block**:

- `mass bundle publish` without the `--development` (`-d`) flag
- Any v2 command targeting a production environment, including `mass instance deploy|destroy|version`, `mass environment update`, `mass component remove` against a prod instance, etc.

Read-only operations (`mass instance get`, `mass deployment logs`, `mass resource get|download`, etc.) are always allowed regardless of environment.

## Configuration

Create `.claude/massdriver.local.md` in your project:

```yaml
---
mass_profile: default
production_pattern: (prod|production)
organization_id: ""
default_test_project: ""
---
```

| Setting | Description |
|---------|-------------|
| `mass_profile` | CLI profile from `~/.config/massdriver/config.yaml` |
| `production_pattern` | Regex to identify production environments (protected) |
| `organization_id` | Default org ID (optional, used when running raw GraphQL mutations) |
| `default_test_project` | Where to create test environments (optional) |

See `massdriver/templates/massdriver.local.md` for full documentation.

## Examples

### Creating a PostgreSQL Bundle

```
/massdriver:develop PostgreSQL database bundle.
Presets: Development (t3.small, 20GB), Staging (t3.medium, 50GB), Production (r6g.large, 100GB, Multi-AZ).
PITR should be configurable, defaulting to enabled.
SSL enforcement is mandatory.
Needs a network connection and AWS credentials.
Produces a postgres resource (artifact field) with connection info.
```

### Creating an S3 Bundle

```
/massdriver:develop S3 bucket for static asset storage.
Developers choose versioning (on/off) and lifecycle policy (30/90/365 days).
Encryption at rest is non-negotiable.
Public access blocked by default but configurable.
Needs AWS credentials, produces an S3 bucket resource.
```

### Testing an Upgrade

```
/massdriver:test-upgrade api-prod-database 1.3.0
```

The agent will ask about your production naming convention, what to copy from prod (secrets, remote refs, env defaults), and whether to mirror or low-scale dependency components.

## Requirements

- [Massdriver CLI v2](https://docs.massdriver.cloud/cli/overview) (`mass`)
- OpenTofu or Terraform
- A Massdriver account with CLI credentials configured

## Learn More

- [Massdriver Documentation](https://docs.massdriver.cloud/)
- [Bundle Development Guide](https://docs.massdriver.cloud/bundles/development)
- [Bootstrap Catalog](https://github.com/massdriver-cloud/massdriver-catalog) (sample bundles + resource types)

## License

Apache 2.0 - See [LICENSE](LICENSE)
