---
name: test-upgrade
description: Test a bundle version upgrade by cloning production package config to a test environment
argument-hint: <package-id> <target-version>
allowed-tools:
  - Task
  - Read
  - AskUserQuestion
---

# Upgrade Testing

Start the upgrade-tester agent to validate a bundle version upgrade against production-like configuration.

## What This Does

1. **Identify instance** - Instance slug specifies exactly which bundle deployment to clone (e.g., `api-prod-database`)
2. **Fork environment** - `fork_environment` creates an isolated test environment carrying prod's component config (secrets/refs/defaults opt-in)
3. **Verify the mirror** - `compare_environments` between prod and the fork
4. **Adjust scale** - Optionally `copy_instance` with `overrides` to reduce non-critical dependency sizes
5. **Baseline deploy** (MCP) - `create_deployment` + `get_deployment_logs follow:true`
6. **Upgrade** (MCP) - `update_instance` to the target version, redeploy, then audit with `compare_deployments`
7. **Report results** - Summary of upgrade success/failure with recommendations

## Usage

Specify the instance slug and target version:

```
/massdriver:test-upgrade api-prod-database 1.3.0
```

```
/massdriver:test-upgrade ecomm-production-redis 2.0.0
```

Instance slugs follow the format: `{project}-{environment}-{component}` (e.g., `api-prod-database`).

If the slug or version aren't specified, the agent will ask.

## Instructions

Use the Task tool to spawn the `upgrade-tester` agent with the upgrade details. The agent will handle the interactive workflow.

Parse the arguments to extract:
- Instance slug (first argument) - identifies the specific instance to clone
- Target version (second argument) - the version to upgrade to

If arguments weren't provided, ask the user for the instance slug and target version.
