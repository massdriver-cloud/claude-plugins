# Massdriver Plugin for Claude Code

Build infrastructure bundles for [Massdriver](https://massdriver.cloud) — the internal developer platform that turns infrastructure-as-code into reusable, self-service components with built-in guardrails.

This plugin is **MCP-first**: all control-plane operations (projects, environments, components, deployments, resources) go through the [Massdriver MCP server](https://github.com/massdriver-cloud/mcp-server), which the plugin registers automatically. The **Massdriver CLI** (`mass`) is still required for filesystem-bound work — bundle build/lint/publish/pull and resource-type publishing.

## Installation

```bash
# Add the marketplace
/plugin marketplace add massdriver-cloud/claude-plugins

# Install the plugin
/plugin install massdriver@massdriver
```

### MCP server setup

The plugin launches the [Massdriver MCP server](https://github.com/massdriver-cloud/mcp-server) via a bundled script ([scripts/run-mcp-server.sh](massdriver/scripts/run-mcp-server.sh)) that runs the official Docker image — no local binary or language toolchain needed. The only prerequisite is **Docker** installed and running (Docker Desktop on macOS/Windows, Docker Engine on Linux).

The script runs the container as your user with `--pull always`, so every Claude Code session starts on the newest published image (an up-to-date image is a fast metadata check, not a re-download), and your `~/.config/massdriver` is mounted read-only when it exists. Both auth modes work out of the box:

```bash
# Option A — environment variables (take precedence):
export MASSDRIVER_API_KEY="your-api-key"
export MASSDRIVER_ORGANIZATION_ID="your-org-id"
export MASSDRIVER_URL="https://api.massdriver.cloud"  # optional; only for self-hosted instances

# Option B — profiles: nothing to do. Your ~/.config/massdriver/config.yaml is
# mounted into the container; the `default` profile is used unless you export
# MASSDRIVER_PROFILE=<name>.
```

Optionally pre-pull before your first session to skip the initial download delay: `docker pull massdrivercloud/mcp-server`.

Verify with `/mcp` in Claude Code — the `massdriver` server should be listed with its tools.

**Troubleshooting:**
- Server shows as failed → the launcher prints the exact reason to stderr (visible via `claude --debug` or the `/plugin` Errors tab): Docker not installed, daemon not running, or missing credentials in the shell that launched Claude Code.
- On native Windows (non-WSL), the launcher requires bash — run Claude Code inside WSL, or override the `massdriver` server in your project `.mcp.json` with a plain `docker` command.

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
3. Sets up project + ephemeral test environment (MCP `create_project` / `create_environment`)
4. Adds the bundle as a component in the project's blueprint (MCP `add_component`)
5. Pins the test instance to the development channel (MCP `update_instance`, version `latest+dev`)
6. Runs deploy loop: MCP `create_deployment` + `get_deployment_logs follow:true`, republishing via CLI as code changes
7. Remediates compliance findings automatically
8. Journals results in the environment description (MCP `update_environment`)

### `/massdriver:test-upgrade` - Day 2 Upgrade Testing

Validate bundle version upgrades by forking the production environment and copying its instance config to a test environment.

```
/massdriver:test-upgrade api-prod-database 1.3.0
```

Instance identifier format `{project}-{environment}-{component}`.

**What it does:**
1. Forks the source instance's environment with `fork_environment`, carrying prod's component config (secrets/remote refs/env defaults opt-in)
2. Verifies the mirror with `compare_environments`, low-scaling non-critical dependencies via `copy_instance` overrides
3. Deploys the current version as a baseline (`create_deployment`)
4. Bumps the version (`update_instance`), redeploys, and audits the change with `compare_deployments`
5. Reports success/failure with recommendations (including `rollback_deployment` as the day-2 escape hatch), then tears down with `decommission_environment`

### `/massdriver:gen` - Quick Scaffolding

Generate a bundle without the deploy loop.

```
/massdriver:gen RDS MySQL for OLTP workloads
```

### `/massdriver:architect` - Citizen Engineer App Design (experimental)

Turn a plain-language app idea into a governed Massdriver project: the agent probes the
(grant-filtered) platform catalog, recommends project layout/bundles/runtime (decisively — it
states its reasoning rather than asking), builds and publishes the app bundle directly to the
platform, and promotes through environments gated by your permissions. If a needed capability
has no granted bundle, it tells the user exactly what to request from their DevOps team instead
of improvising infrastructure.

```
/massdriver:architect a serverless API that resizes uploaded images and stores them in S3
```

## How It Works

The plugin drives the Massdriver control plane through the official MCP server (100 tools):

- **Deploys**: `create_deployment` (`PROVISION`/`PLAN`/`DECOMMISSION`) + `get_deployment_logs` with `follow: true`. Params travel with each deployment call.
- **Blueprint composition**: `add_component` / `link_components` — components are added once at the project level; every environment auto-gets an instance.
- **Day 2 operations**: deployment approval flow (`propose_deployment` → human approves), `rollback_deployment`, `plan_deployment`, `compare_environments`, `compare_deployments`, instance secrets, remote references.
- **Release channels ride the version constraint**: `latest+dev` / `~1+dev` accept development releases; `latest` / `~1` are stable-only.
- **Environment-scale operations**: `fork_environment` (test envs from prod), `deploy_environment` / `decommission_environment` (whole-environment waves in dependency order), `copy_instance` (config mirroring with overrides).
- **The CLI handles filesystem work**: `mass bundle build|lint|new|publish|pull`, `mass resource-type publish|get|list`, and `mass server`.

## What This Plugin Does

This plugin helps platform engineers create and test Massdriver bundles — reusable IaC modules that package OpenTofu, Terraform, or Helm with input schemas, resource type contracts, and operational policies.

**Capabilities:**
- **MCP-native operations**: Auto-registers the Massdriver MCP server; all control-plane work uses typed tools instead of shelling out
- **Interactive development**: Full deploy loop with compliance remediation
- **Upgrade testing**: Validate version upgrades against production configs (`fork_environment` + `copy_instance`, verified with `compare_environments`)
- **Safety guardrails**: Blocks non-development publishes and production-targeting writes — across BOTH `mass` CLI commands and MCP tool calls, including automated deployment approval
- **Compliance automation**: Iterates until Checkov findings are resolved
- **GraphQL reference**: Multi-entity queries for when one query beats a chain of tool calls

## When It Activates

The plugin auto-activates when:
- Working in `bundles/`, `resource-type/`, `platforms/`, or `projects/` directories
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
    ├── .mcp.json                   # Points at the MCP launcher script
    ├── scripts/
    │   ├── run-mcp-server.sh       # Runs the Massdriver MCP server via Docker
    │   ├── massdriver-safety-check.sh  # Deterministic PreToolUse guard (CLI + MCP)
    │   └── test-safety-check.sh    # Test suite for the safety guard
    ├── agents/
    │   ├── architect.md            # Citizen-engineer project design (experimental)
    │   ├── bundle-dev.md           # Full development workflow
    │   └── upgrade-tester.md       # Day 2 upgrade testing
    ├── commands/
    │   ├── architect.md            # /massdriver:architect
    │   ├── develop.md              # /massdriver:develop
    │   ├── test-upgrade.md         # /massdriver:test-upgrade
    │   └── gen.md                  # /massdriver:gen
    ├── hooks/
    │   └── hooks.json              # Safety guardrails (CLI + MCP tool calls)
    ├── templates/
    │   └── massdriver.local.md     # Settings template
    └── skills/
        └── massdriver/
            ├── SKILL.md            # Core knowledge (mental model + workflows)
            ├── PATTERNS.md         # Bundle and resource type examples
            ├── snippets/           # Copy-paste templates
            └── references/
                ├── graphql.md      # GraphQL multi-entity queries
                ├── alarms.md       # AWS/GCP/Azure monitoring
                └── compliance.md   # Checkov remediation
```

## Safety Guardrails

The plugin includes a deterministic safety hook (`scripts/massdriver-safety-check.sh`, no LLM in the loop) covering **both the CLI and the MCP tools**, which **hard blocks**:

- `mass bundle publish` without the `--development` (`-d`) flag
- Any CLI command or MCP mutation targeting a production environment: `create_deployment` / `propose_deployment` (`PROVISION` and `DECOMMISSION`), `update_instance`, instance secrets, remote references, `update_environment` / `delete_environment`, environment defaults, and prod-referencing resource mutations. **Plans are exempt** — `PLAN` deployments and `mass instance deploy --plan` are dry-runs and allowed on any environment, including production.
- `approve_deployment` — always, regardless of target. Approving proposed deployments (including rollbacks) is a human authorization step; agents can propose, humans approve in the UI.

Read-only MCP tools (`get_*`, `list_*`, `compare_*`, `evaluate_*`, `explain_*`) are auto-approved — no permission prompt, on any environment. `export_resource` still prompts since it returns unmasked secrets. Non-applying tools (`plan_deployment`, `rollback_deployment`, `reject_deployment`, `abort_deployment`) are allowed since they cannot change infrastructure without a human approval.

The production pattern is substring-matched against the **environment segment** of slugs only — a component *named* `prodcache` in a test environment is not blocked, while an environment named `preprod` is. Anything the hook has no opinion on falls through to Claude Code's normal permission prompt. The policy is tested: `scripts/test-safety-check.sh`.

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
| `mass_profile` | Profile from `~/.config/massdriver/config.yaml`, used by the `mass` CLI. The MCP server reads the same file (mounted into its container) via `MASSDRIVER_PROFILE` |
| `production_pattern` | Regex to identify production environments (protected by hooks on both CLI and MCP calls) |
| `organization_id` | Default org ID (optional, used when running raw GraphQL queries; the MCP server gets its org from its own env/profile) |
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

## Local Development & Testing (plugin contributors)

Test plugin changes straight from a working tree — no publish, no reinstall, nothing lands in `main`:

```bash
# 1. Work on a branch so main stays clean
git checkout -b my-change

# 2. Disable the marketplace-installed copy so it can't shadow your local one
claude plugin disable massdriver

# 3. Launch a session that loads the plugin from disk (this session only)
claude --plugin-dir /path/to/claude-plugins/massdriver
```

The MCP server registers from the local plugin too (Docker still required — see Installation).

Smoke test inside that session:
- `/mcp` — confirm the `massdriver` server is listed with its tools
- Run a command (e.g. `/massdriver:develop ...`) and confirm it routes to the right agent
- `/agents` — confirm the plugin's agents are registered
- Try `mass bundle publish` (no `-d`) — the safety hook should block it (`scripts/test-safety-check.sh` runs the full policy suite)

**Iterate:** `--plugin-dir` reads the live directory, so edit files → restart the session → retest. No republish cycle.

Validate manifests anytime:

```bash
claude plugin validate ./massdriver   # plugin.json
claude plugin validate .              # marketplace.json
```

When you're done: `claude plugin enable massdriver` to restore the installed copy. To ship: PR the branch into `main`, bump `version` in `massdriver/.claude-plugin/plugin.json`, merge; installed copies pick it up with `claude plugin update massdriver` (restart required).

## Requirements

- Docker (runs the [Massdriver MCP server](https://github.com/massdriver-cloud/mcp-server) — see Installation)
- [Massdriver CLI](https://docs.massdriver.cloud/cli/overview) (`mass`) — for bundle/resource-type publishing and local builds
- OpenTofu or Terraform
- A Massdriver account, with either an API key exported (`MASSDRIVER_API_KEY` + `MASSDRIVER_ORGANIZATION_ID`) or a profile in `~/.config/massdriver/config.yaml`

## Learn More

- [Massdriver Documentation](https://docs.massdriver.cloud/)
- [Bundle Development Guide](https://docs.massdriver.cloud/bundles/development)
- [Bootstrap Catalog](https://github.com/massdriver-cloud/massdriver-catalog) (sample bundles + resource types)

## License

Apache 2.0 - See [LICENSE](LICENSE)
