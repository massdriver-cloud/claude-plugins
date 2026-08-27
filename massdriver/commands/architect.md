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

> **Placeholder / demo command.** Citizen developers — non-infra folks vibe-coding an app with an
> LLM — shouldn't end up with an unreviewed pile of infrastructure on a laptop. This command
> routes that work through Massdriver's self-service portal instead: it lands in the org's cloud
> account, on secure/compliant/**correct** bundles, inside a visual, audit-filled environment
> with a full deployment history.

Start the `architect` agent to take an app idea and turn it into a real Massdriver project:
the right project layout, the right bundles, the right runtime, and a permission-gated path
from dev up through production.

## What This Does

1. **Setup** — asks which environment and which credentials/profile to work in.
2. **Understand the use case** — what the citizen developer is actually trying to ship.
3. **Recommend a project layout** — one project vs. sharded projects, environment defaults,
   and remote references for shared/cross-project resources.
4. **Recommend bundles** — reuse existing org bundles where they fit; identify where a
   custom application bundle is needed. If the app needs a capability with no bundle in the
   (grant-filtered) catalog, the agent won't improvise infrastructure — it tells the user
   exactly what to request from their DevOps team, and keeps building the rest.
5. **Pick a runtime** — examines the use case against the org's available bundles,
   environments, and standards, then picks the best runtime and proceeds. It states its
   reasoning; it doesn't make the citizen developer choose. See below.
6. **Build + publish the app bundle directly to the platform** (`--development`) so the
   citizen developer never needs a git remote or a PR to get moving. Source is committed to a
   **local** git repo automatically; a remote is opt-in (the agent asks if one already exists).
7. **Progress through environments** — dev → staging → prod, gated by the user's permissions.

The whole flow is meant to be as frictionless as: **install Claude → install the Massdriver
plugin → set access keys → `/massdriver:architect`.** No git hosting, CI, or repo permissions
required.

## Runtime Selection

The architect doesn't ask the user to pick a runtime — that's the expertise it supplies. It
examines the use case and the org's (grant-filtered) catalog and standards, states its pick
with the reasoning, and keeps moving:

> "Given the use case, you have **Lambda** or **Kubernetes** deployments available. Kubernetes
> makes the most sense here because <x> — building your container and pushing to your ECR now."

- **Containers** (Kubernetes/ECS/etc.) when the app is long-running, needs persistent
  connections, or the org has standardized on clusters — the agent writes the Dockerfile,
  builds and pushes the image to the org's granted registry (e.g. ECR), and builds the app
  bundle to deploy onto a cluster the user has access to.
- **Serverless** (e.g. Lambda) for event-driven or request-scoped workloads, or when it's the
  only granted runtime.

If the user pushes back, the agent adjusts — but it never opens with a question.

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
