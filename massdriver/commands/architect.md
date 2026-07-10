---
name: architect
description: Turn an app idea into governed infrastructure via Massdriver's self-service portal
argument-hint: <app idea / use-case description>
allowed-tools:
  - Task
  - Read
  - AskUserQuestion
---

# Architect — App Idea → Governed Infrastructure

> **Placeholder / demo command.** Citizen engineers — non-infra folks vibe-coding an app with an
> LLM — shouldn't end up with an unreviewed pile of infrastructure on a laptop. This command
> routes that work through Massdriver's self-service portal instead: it lands in the org's cloud
> account, on secure/compliant/**correct** bundles, inside a visual, audit-filled environment
> with a full deployment history.

Start the `architect` agent to take an app idea and turn it into a real Massdriver project:
the right project layout, the right bundles, the right runtime, and a permission-gated path
from dev up through production.

## What This Does

1. **Setup** — asks which environment and which credentials/profile to work in.
2. **Understand the use case** — what the citizen engineer is actually trying to ship.
3. **Recommend a project layout** — one project vs. sharded projects, environment defaults,
   and remote references for shared/cross-project resources.
4. **Recommend bundles** — reuse existing org bundles where they fit; identify where a
   custom application bundle is needed. If the app needs a capability with no bundle in the
   (grant-filtered) catalog, the agent won't improvise infrastructure — it tells the user
   exactly what to request from their DevOps team, and keeps building the rest.
5. **Pick a runtime** — inspect the platform for what's available (container registry vs.
   serverless) and choose. See the stub logic below.
6. **Build + publish the app bundle directly to the platform** (`--development`) so the
   citizen engineer never needs a git remote or a PR to get moving. Source is committed to a
   **local** git repo automatically; a remote is opt-in (the agent asks if one already exists).
7. **Progress through environments** — dev → staging → prod, gated by the user's permissions.

The whole flow is meant to be as frictionless as: **install Claude → install the Massdriver
plugin → set access keys → `/massdriver:architect`.** No git hosting, CI, or repo permissions
required.

## Runtime Selection (stub behavior)

The architect inspects what the platform actually offers and picks a runtime:

- If it sees a **container registry** available → containerized runtime (ECS/Cloud Run/etc.).
- If it sees **Lambda** (serverless) and **no** container registry → serverless runtime.

For the demo, the platform has Lambda but no Docker registry, so the architect will **stub out
to Lambda** and say so explicitly. It will also make clear that this is a config-driven choice:

```jsonc
// massdriver.config.json  (project root)
{
  "useDocker": true   // <- flip this and the architect would build a container runtime instead
}
```

If `massdriver.config.json` sets `useDocker: true` (or names a specific registry/runtime), the
architect honors that instead of inferring from the platform.

## Usage

```
/massdriver:architect a WordPress site for our marketing team
```

```
/massdriver:architect a serverless API that resizes uploaded images and stores them in S3
```

If no idea is provided, the agent will ask what you want to build.

## Instructions

Use the Task tool to spawn the `architect` agent with the user's app idea. The agent handles
the interactive workflow, starting with credentials/environment setup, then the four opening
questions: **What environment? What credentials? What's the use case?** → then it recommends
**project layout, bundles, and runtime**.

If no app idea was provided in the command arguments, ask the user what they want to build.
