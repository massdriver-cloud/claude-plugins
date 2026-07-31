---
name: develop
description: Start interactive bundle development workflow with full deploy loop and compliance remediation
argument-hint: <use-case description>
allowed-tools:
  - Task
  - Read
  - AskUserQuestion
---

# Bundle Development

Start the bundle-dev agent to guide you through creating and testing a Massdriver infrastructure bundle.

## What This Does

1. **Setup** - Verify MCP auth (`get_viewer`) and select/create the target project + environment (MCP `create_project` / `create_environment`)
2. **Gather requirements** - Understand your use case, developer UX needs, and compliance strategy
3. **Scaffold bundle** - Create massdriver.yaml, Terraform code, and supporting files
4. **Publish bundle** (CLI) - `mass bundle publish --development`
5. **Add to project blueprint** (MCP) - `add_component` (once per project)
6. **Pin development channel** (MCP) - `update_instance` with version `latest+dev`
7. **Deploy & iterate** (MCP) - `create_deployment` + `get_deployment_logs follow:true`, re-publishing and redeploying as code changes
8. **Remediate compliance** - Fix Checkov findings according to your strategy
9. **Journal results** (MCP) - Record what was tested via `update_environment`

## Usage

Provide a description of what bundle you want to create:

```
/massdriver:develop PostgreSQL database for application backends with dev/staging/prod presets
```

```
/massdriver:develop S3 bucket for static asset storage with CloudFront CDN
```

```
/massdriver:develop EKS cluster with managed node groups and cluster autoscaler
```

## Instructions

Use the Task tool to spawn the `bundle-dev` agent with the user's use case description. The agent will handle the interactive workflow, starting with credential/environment setup.

If no use case was provided in the command arguments, ask the user what bundle they want to develop.
