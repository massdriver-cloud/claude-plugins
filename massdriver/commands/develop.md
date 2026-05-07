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

1. **Setup credentials, project & environment** - Ask for CLI profile and target project + environment (project + env can both be created via CLI in v2)
2. **Gather requirements** - Understand your use case, developer UX needs, and compliance strategy
3. **Scaffold bundle** - Create massdriver.yaml, Terraform code, and supporting files
4. **Publish bundle** - `mass bundle publish --development`
5. **Add to project blueprint** - `mass component add <project> <bundle> --id <comp-id>` (once per project)
6. **Pin release channel** - `mass instance version <project>-<env>-<comp>@latest --release-channel development`
7. **Deploy & iterate** - `mass instance deploy <slug> --params=... --message "..." --follow`, then `--patch` for surgical edits
8. **Remediate compliance** - Fix Checkov findings according to your strategy
9. **Journal results** - Record what was tested via `mass environment update --description "..."`

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
