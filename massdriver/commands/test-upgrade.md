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
2. **Fork environment** - Create isolated test environment via the `forkEnvironment` GraphQL mutation (no CLI verb yet)
3. **Seed config** - Use `copyInstance` (GraphQL) to mirror prod config onto the forked instance
4. **Adjust scale** - Optionally use `copyInstance` `overrides` to reduce non-critical dependency sizes
5. **Baseline deploy** - `mass instance deploy <slug> --message "Baseline" --follow`
6. **Upgrade** - `mass instance version <slug>@<target>` then `mass instance deploy <slug> --message "Upgrade test" --follow`
7. **Report results** - Summary of upgrade success/failure with recommendations

## Usage

Specify the instance slug and target version:

```
/massdriver:test-upgrade api-prod-database 1.3.0
```

```
/massdriver:test-upgrade ecomm-production-redis 2.0.0
```

Instance slugs follow the v2 format: `{project}-{environment}-{component}` (e.g., `api-prod-database`).

If the slug or version aren't specified, the agent will ask.

## Instructions

Use the Task tool to spawn the `upgrade-tester` agent with the upgrade details. The agent will handle the interactive workflow.

Parse the arguments to extract:
- Instance slug (first argument) - identifies the specific instance to clone
- Target version (second argument) - the version to upgrade to

If arguments weren't provided, ask the user for the instance slug and target version.
