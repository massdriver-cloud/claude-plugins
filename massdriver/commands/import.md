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

Start the `resource-import` agent to bring a cloud resource that already exists — created by
hand, by another IaC tool, or in another account — into Massdriver.

## What This Does

The command asks **how** you want to import *before* spawning any agent, then the
`resource-import` agent runs the matching workflow:

1. **New bundle (Path A)** — Author a new reusable bundle whose IaC will manage the resource,
   publish it, add it as a component (MCP `add_component`), then import the live resource into
   that instance's state.
2. **Existing bundle (Path B)** — Reuse a published bundle, create or pick an **undeployed**
   instance, then import into its state.
3. **Register resource only (Path C)** — Create an `EXTERNAL` Massdriver resource so other
   components can connect to it. Massdriver never deploys, changes, or destroys it. No IaC.

Paths A and B put the resource under Massdriver's IaC management; Path C only makes it
referenceable on the canvas.

Bundles have to stay reusable, so adoption uses the imperative `tofu import` command against the
instance's Massdriver-managed HTTP state backend — **never `import {}` blocks**, which would
hardcode one cloud resource ID into source shared by every instance. The import runs locally; the
plan runs in Massdriver's provisioner (MCP `create_deployment` with `action: PLAN`, read via
`get_deployment_logs`), never `tofu plan` locally. The agent loops import → publish →
`update_instance` → re-plan until the plan shows no changes, before anything is deployed.

> Unrelated to `mass bundle import`, which scans a bundle's IaC for variables not yet exposed as
> Massdriver params.

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

**Ask the import path yourself, with `AskUserQuestion`, BEFORE spawning any agent.** Do not defer
it into the subagent and do not assume it — the three paths have very different mechanics and
blast radius.

1. If no resource description was given in the command arguments, ask the user what they want to
   import.
2. Use `AskUserQuestion` to choose the path:
   - **New bundle (Path A)** — Author a new reusable bundle whose IaC manages the resource, then
     import into a new instance's state. Best when no suitable bundle exists.
   - **Existing bundle (Path B)** — Use a published bundle, create/pick an undeployed instance,
     then import into its state. Best when a suitable bundle already exists.
   - **Register resource only (Path C)** — Create an `EXTERNAL` resource so other components can
     connect to it. No IaC; Massdriver does not manage its lifecycle.

   If the user is unsure, ask what they need: *manage* the resource (change/deploy/destroy) → A
   or B; only let components *connect* to it → C.
3. Use the Task tool to spawn the `resource-import` agent, passing **both the resource
   description and the chosen path (A/B/C)**. The agent will:
   - Confirm the already-chosen path and go straight to that workflow (it should NOT re-ask).
   - Verify MCP auth (`get_viewer`) and the CLI profile (`mass whoami`), then set up only the
     credentials that path needs — Paths A/B need an organization slug + API key exported for the
     state backend plus local cloud credentials for the provider; Path C needs neither.
   - Run the workflow and report what was imported, whether the plan is clean, and what is left
     for a human to authorize.
