---
name: import
description: Import an existing cloud resource into Massdriver — as a new bundle, into an existing bundle, or as a standalone resource
argument-hint: <description of the resource to import>
allowed-tools:
  - Task
  - Read
  - AskUserQuestion
---

# Import Existing Cloud Resource

Start the resource-import agent to bring an existing cloud resource (created by hand, another IaC tool, or another account) under Massdriver v2.

## What This Does

The command first asks **how** you want to import — before spawning any agent — then the `resource-import` agent runs the matching workflow:

1. **New bundle (Path A)** — Author a brand-new reusable bundle whose IaC will manage the existing resource. Create an instance in Massdriver where state will be imported. Best when no bundle exists yet.
2. **Existing bundle (Path B)** — Use an existing bundle for IaC, and create a new instance in Massdriver where state will be imported. Best when a suitable bundle already exists.
3. **Register resource only (Path C)** — Create an `EXTERNAL` Massdriver resource that represents the cloud resource so other components can connect to it. Massdriver does NOT manage or deploy it. No IaC.

Paths A and B put the resource under Massdriver's IaC management (via `tofu import` against the instance's Massdriver-managed state — no `import {}` blocks, which would break bundle reusability); Path C only makes it referenceable. The agent imports locally, then loops `mass instance deploy --plan` (the plan runs in Massdriver's provisioner, never `tofu plan` locally) until the plan is clean before anything is deployed.

## Usage

Describe the resource you want to import:

```
/massdriver:import existing production RDS Postgres instance created by hand
```

```
/massdriver:import legacy S3 bucket we manage in Terraform elsewhere — just need components to connect to it
```

```
/massdriver:import bring our manually-created GKE cluster under a new bundle
```

## Instructions

**Ask the import path yourself, with `AskUserQuestion`, BEFORE spawning any agent.** Do not defer it into the subagent, and do NOT assume the path; the three options have very different mechanics and blast radius. Follow these steps:

1. If no resource description was provided in the command arguments, first ask the user what they want to import.
2. Use `AskUserQuestion` to choose the import path. Present three options:
   - **New bundle (Path A)** — Author a brand-new reusable bundle whose IaC manages the resource, then import into a new instance's managed state. Best when no suitable bundle exists.
   - **Existing bundle (Path B)** — Use an existing bundle, create/pick an undeployed instance, then import into its managed state. Best when a suitable bundle already exists.
   - **Register resource only (Path C)** — Create an `EXTERNAL` Massdriver resource so other components can connect to it. No IaC; Massdriver does not manage/deploy/destroy it.

   If the user is unsure, ask what they need: *manage* the resource (change/deploy/destroy it) → A or B; only let components *connect* to it → C.
3. Once the path is known, use the Task tool to spawn the `resource-import` agent, passing **both the resource description and the chosen path (A/B/C)**. The agent will:
   - Confirm the already-chosen path and jump straight to the matching workflow (it should NOT re-ask).
   - Set up only the credentials that path needs (Paths A/B need a Massdriver org ID + API key for the managed-state backend; Path C needs neither).
   - Run the corresponding workflow and report results.
