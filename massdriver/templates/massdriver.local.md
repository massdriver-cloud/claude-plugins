---
# Massdriver Plugin Settings
#
# Copy this file to your project's .claude/ directory:
#   cp templates/massdriver.local.md .claude/massdriver.local.md
#
# These settings customize how the Massdriver plugin behaves.

# CLI profile to use (from ~/.config/massdriver/config.yaml)
# The agent will ask you at session start, but you can pre-set it here.
# Leave blank to use default profile.
mass_profile: ""

# Regex pattern to identify production environments
# The plugin will BLOCK any commands targeting environments matching this pattern
# Examples:
#   - "prod" matches: myapp-prod-db, production, prod-east
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

Environments matching the `production_pattern` above are protected:
- Cannot deploy instances in them (`mass instance deploy|destroy|version`)
- Cannot mutate the environment record (`mass environment update`)
- Cannot remove components/resources tied to a prod instance

Read-only operations (`mass instance get`, `mass deployment logs`, `mass resource get|download`, etc.) are always allowed.

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
