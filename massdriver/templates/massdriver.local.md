---
# Massdriver Plugin Settings
#
# Copy this file to your project's .claude/ directory:
#   cp templates/massdriver.local.md .claude/massdriver.local.md
#
# These settings customize how the Massdriver plugin behaves.

# Profile to use (from ~/.config/massdriver/config.yaml)
# Used by the `mass` CLI for publish/build steps.
# The agent will ask you at session start, but you can pre-set it here.
# Leave blank to use default profile.
mass_profile: ""

# Regex pattern to identify production environments
# The plugin will BLOCK any CLI commands OR MCP tool calls targeting
# environments matching this pattern.
#
# The pattern is substring-matched against the ENVIRONMENT SEGMENT of a
# slug only — never the whole slug and never free-text fields:
#   - instance slug myapp-prod-db      -> env segment "prod"    -> blocked
#   - env slug myapp-preprod           -> env segment "preprod" -> blocked (substring)
#   - instance slug myapp-testa-prodcache -> env segment "testa" -> allowed
#     (a component *named* prodcache does not trigger the guard)
# Anchor the regex if you want exact matching: "^(prod|production)$"
#
# Examples:
#   - "prod" matches: myapp-prod-db, production, prod-east, preprod
#   - "(prod|production)" matches: prod OR production
#   - "prd-.*" matches: prd-east, prd-west
production_pattern: (prod|production)

# Default project for test environments (optional)
# If set, bundle-dev agent will offer to create test envs here
default_test_project: ""
---

# Massdriver Settings

This file configures the Massdriver plugin for this project (v2).

## Production Protection

Environments matching the `production_pattern` above are protected across BOTH the `mass` CLI and the Massdriver MCP tools:
- Cannot create `PROVISION` or `DECOMMISSION` deployments against them (`PLAN` dry-runs are allowed — they don't alter infrastructure)
- Cannot mutate instances (`update_instance`, secrets, remote references) or the environment record (`update_environment`, `delete_environment`, defaults)
- Cannot remove components/resources tied to a prod instance
- `approve_deployment` is always blocked — approving proposed deployments is human-only

Read-only operations (`get_*`, `list_*`, `compare_*`, `get_deployment_logs`, etc.) are auto-approved — they never trigger a permission prompt. `export_resource` is the one read that still prompts, since it returns unmasked secrets.

This file is resolved relative to the session working directory (`<cwd>/.claude/massdriver.local.md`). Subagents or worktrees running from a different directory fall back to the default pattern unless the file exists there too.

## Test Environment Naming

The plugin creates test environments with the pattern `agent<RANDOM>`:
- `agentx7k2m9` - 6 random hex characters
- Environment full slug: `<project>-agent<random>` (e.g., `claude-agentx7k2m9`)
- Instance slugs: `<project>-<env>-<component>` (e.g., `claude-agentx7k2m9-postgres`)

**Important**: Instance slugs already include the project segment. Never double-prefix.

## Profile Configuration

If you have multiple Massdriver CLI profiles, set `mass_profile` to the one
this project should use. Profiles are defined in `~/.config/massdriver/config.yaml`.

Alternatively, the agent will ask you at the start of each session.
If using an alternate profile, the agent sets `MASSDRIVER_PROFILE=<name>`.
