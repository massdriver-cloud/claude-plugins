# Importing Existing Cloud Resources (v2)

How to bring cloud infrastructure that already exists (created by hand, by another IaC tool, or by a different account/team) under Massdriver management.

There are **three distinct paths**. Pick based on whether the user wants Massdriver's IaC to *manage* the resource, or merely *represent* it so other components can connect to it. **Always confirm the path with the user before doing any work** — the mechanics and blast radius differ sharply.

| Path | What it does | Massdriver manages the infra? | When to use |
|------|--------------|-------------------------------|-------------|
| **A. New bundle** | Author a brand-new reusable bundle, create an instance, and import the resource into that instance's state | ✅ Yes (going forward) | No suitable bundle exists yet; you want a reusable, self-service component |
| **B. Existing bundle** | Use an existing bundle, create/pick an undeployed instance, and import the resource into that instance's state | ✅ Yes (going forward) | A suitable bundle already exists |
| **C. Register a Massdriver resource** | Create an `EXTERNAL` resource record that represents the cloud resource — no IaC, no state | ❌ No (stays externally managed) | You only need other components to *connect* to it; you don't want Massdriver to touch it |

---

## The import mechanism (shared by Paths A and B)

**Bundles must stay reusable, so they must NOT contain `import {}` blocks.** An `import {}` block hardcodes a specific cloud resource ID into the bundle source, which would break reuse across instances. Instead, run the **imperative `tofu import` / `terraform import` command** from your machine, pointed at the target instance's **Massdriver-managed state**.

Docs: https://docs.massdriver.cloud/platform-operations/state-management

### Prerequisite: both the bundle AND an instance must exist

State is per-instance, so there must be an instance to import into *before* you can import anything:

- **New bundle (Path A)**: author the bundle, `mass bundle publish --development`, then `mass component add <project> <bundle> --id <comp>` — every environment in the project now has an instance. Leave the target instance **undeployed**.
- **Existing bundle (Path B)**: ask the user whether to **create a new instance** or import into an **existing undeployed instance**.

### The bundle backend must be Massdriver-compatible

Massdriver-managed state requires **either no backend block at all, or an empty `http` backend**:

```hcl
# Acceptable — no backend block (Massdriver injects the http backend)

# ...or an explicit empty http backend:
terraform {
  backend "http" {}
}
```

If an `http` backend is declared it MUST be empty — all configuration comes from the env vars below. **Any other backend (`s3`, `gcs`, `azurerm`, a configured `http`, etc.) is incompatible: that bundle is NOT using Massdriver-managed state and import cannot be completed.** Verify this before proceeding with Path B.

> **Critical for local import — a bundle with *no* backend block needs a temporary local-only `http` backend override.** OpenTofu/Terraform only honor the `TF_HTTP_*` env vars if an `http` backend is actually declared. If the bundle has no backend block (relying on Massdriver to inject one at deploy time), a local `tofu init` / `tofu import` will **silently ignore** `TF_HTTP_*` and write to a throwaway *local* `terraform.tfstate`. The import looks like it succeeded, but the first `mass instance deploy --plan` then shows **every resource as "to add"** because the real remote state is still empty. To avoid this, drop a **local-only** override file in the bundle's step dir before importing:
>
> ```hcl
> # backend_override.tf — LOCAL ONLY. Never commit, and never publish.
> terraform {
>   backend "http" {}
> }
> ```
>
> **Delete it as soon as the import loop is done**, and make sure it is never included in `mass bundle publish` — the bundle's real source must stay backend-less so Massdriver injects the backend at deploy time. Bundles that already declare an empty `http` backend don't need this override.

### Point tofu/terraform at the instance's managed state

Set these before `init`/`import`/`plan`:

```bash
export TF_HTTP_USERNAME=${MASSDRIVER_ORG_ID}      # your Massdriver org ID
export TF_HTTP_PASSWORD=${MASSDRIVER_API_KEY}     # a Massdriver API key

# Intermediate convenience vars — NOT required if you set TF_HTTP_ADDRESS directly
export MASSDRIVER_INSTANCE_ID="<instance-id>"
export MASSDRIVER_BUNDLE_STEP_NAME="<step-name-in-your-bundle>"

export TF_HTTP_ADDRESS="https://api.massdriver.cloud/state/${MASSDRIVER_INSTANCE_ID}/${MASSDRIVER_BUNDLE_STEP_NAME}"
export TF_HTTP_LOCK_ADDRESS=${TF_HTTP_ADDRESS}
export TF_HTTP_UNLOCK_ADDRESS=${TF_HTTP_ADDRESS}
```

- `MASSDRIVER_INSTANCE_ID` and `MASSDRIVER_BUNDLE_STEP_NAME` are only intermediates used to build `TF_HTTP_ADDRESS`. As long as `TF_HTTP_ADDRESS` (and the lock/unlock addresses) are correct, they aren't strictly necessary.
- The step name is the step key in the bundle's `steps:` config (commonly `src`).
- **Don't hand-assemble the URL if you're unsure.** Run `mass instance get <instance-id> -o json` — the `statePaths` section lists every step and its exact state URL. Copy the right one straight into `TF_HTTP_ADDRESS`.

### Import loop

Run `import` **locally**, but run the **plan through Massdriver** — never `tofu plan` locally.

```bash
cd bundles/<bundle>/src
tofu init                                             # local — initializes the HTTP backend against the instance's state
tofu import <resource.address> <cloud-provider-id>    # local — once per resource; writes to managed state

mass instance deploy <project>-<env>-<comp> --plan    # runs the plan in Massdriver's provisioner; goal: "No changes"
```

1. Run `tofu import` (or `terraform import`) **once per resource** in the module. This is safe to run locally — it only writes to the managed state.
2. **Do NOT run `tofu plan` locally.** The local machine may not have valid cloud credentials, local runs are untracked/unaudited, and compliance tooling only runs in the provisioner. Instead run **`mass instance deploy --plan`**, which executes the plan (the same way a real deploy would) inside Massdriver's provisioner.
3. A **clean plan (no changes)** means the imported state matches the config. If it's **not** clean: update the HCL to match reality, then:
   ```bash
   mass bundle publish --development                       # creates a NEW development version
   mass instance version <project>-<env>-<comp>@<version>  # point the instance at the version you just published
   mass instance deploy <project>-<env>-<comp> --plan      # re-plan
   ```
   **Loop until the plan is clean.**
4. When every resource is imported and the plan is clean, the import is complete — tell the user.

> **Move the instance to the version you just published before re-planning.** `mass bundle publish --development` creates a new development version, but the instance keeps running whatever version it's currently pinned to. If you skip `mass instance version <project>-<env>-<comp>@<version>`, the plan executes the *older* version and your fixes won't show up. (Use the exact version string printed by the publish, or `mass instance get <instance-id> -o json` to confirm the resolved version.)

> **`import` and a plan do not mutate cloud infrastructure.** `import` only writes to state; `--plan` is plan-only (no apply). The dangerous step is a subsequent **deploy/apply** while the plan is not clean — never deploy until the plan is clean, and production deploys require explicit human authorization (the safety hook blocks them).

> **When the plan can't go fully clean, finish with one deploy — never hand-edit state.** Some config attributes have no cloud-API representation and so cannot be seeded by `tofu import`. The plan keeps showing that benign diff no matter how many times you re-import, so the "loop `--plan` until clean" model can't terminate on its own. When the **only** remaining changes are benign — the plan shows **`0 to destroy` and `0 to replace`**, and every change is a metadata/bookkeeping write (e.g. the `massdriver_artifact` record), a state-only attribute, or a no-op re-render — run **one real `mass instance deploy -m "..."`** (allowed outside production) to reconcile state to config, then confirm the next `--plan` is clean. This is the correct finish, not a safety violation. **Do NOT resolve this with direct state edits** — all state interactions go through `tofu import` and `deploy`; hand-editing state over the `http` backend is off-limits (it risks corrupting lineage/serial and bypasses the audited path).

> **Existing-bundle caution (Path B):** editing an existing bundle's code affects **every instance using it**. PROMPT THE USER before changing an existing bundle's source during the plan-clean loop.

---

## Path A — New bundle for the cloud resource

1. **Discover the live resource** — get its provider resource ID and current configuration via the cloud CLI (`aws ... describe`, `gcloud`, `az`). Capture everything Terraform treats as required or replacement-forcing.
2. **Author a well-formed bundle.** Use the **`bundle-dev` agent** (or its guidance in `SKILL.md`) to understand what a good bundle looks like — provider block (fetch the resource type first with `mass resource-type get <platform>`), `massdriver.yaml` params/connections/artifacts, and the empty `http` backend.
   - **Scope the bundle to the resource AND its immediate dependencies.** A good bundle encapsulates the resource together with the things that belong to it in a properly scoped module. Importing a *database*, for example, should also pull in its security group, parameter/config group, subnet group, etc. — not just the DB.
   - For anything **ambiguous** (unclear whether a resource belongs in this bundle), **ask the user** whether to include it.
3. **Publish + add to the blueprint** so an instance exists:
   ```bash
   mass bundle publish --development
   mass component add <project> <bundle> --id <comp> --name "<Display Name>"
   ```
4. **Import into the instance's state** using the shared mechanism above (compatible backend → env vars → `tofu import` per resource locally → `mass instance deploy --plan` until clean).
5. Report completion to the user.

---

## Path B — Existing bundle

1. **Identify the existing bundle** and confirm it uses an **empty `http` backend** (otherwise it's not on Massdriver-managed state — stop). Pull the source with `mass bundle pull <name>` if needed.
2. **Establish the target instance** — ask the user whether to create a new instance or import into an existing **undeployed** instance.
3. **Discover the live resource** (as in Path A step 1).
4. **Import into the instance's state** using the shared mechanism above.
5. During the plan-clean loop, **prompt the user before editing the bundle** — changes affect all instances using it.
6. Report completion to the user.

---

## Path C — Register a Massdriver resource (no bundle)

Goal: make an externally-managed cloud resource visible in Massdriver so other components can **connect** to it. Massdriver never provisions, deploys, or destroys it — it's a reference record with `EXTERNAL` status. No state, no IaC, no import command.

**CLI (preferred when available):**
```bash
# Build a payload matching the resource type's schema
cat > /tmp/payload.json <<'EOF'
{ ...fields required by the resource type... }
EOF

mass resource create -n "<name>" -t <resource-type> -f /tmp/payload.json
```

**GraphQL (equivalent, when you need org-scoping or the CLI verb is unavailable):**
```graphql
mutation {
  createResource(
    organizationId: "<org-id>"
    input: {
      name: "External RDS"
      resourceTypeId: "postgres"
      payload: { ... matches resource type schema ... }
    }
  ) { successful result { id name } messages { message } }
}
```

Notes:
- The `payload` **must** validate against the resource type's schema. Fetch it first: `mass resource-type get <resource-type>`.
- The resulting resource ID is a **UUID** (imported/external resources), as opposed to the `<project>-<env>-<component>-<field>` slug used by provisioned resources. See `references/graphql.md`.
- To make it the default a component connects to in an environment: `mass environment default <project>-<env> <resource-id>`.
- This path does NOT bring the resource under IaC management. If the user later wants Massdriver to manage it, that's Path A or B.

---

## Choosing quickly

- "I want a reusable component and there's no suitable bundle yet" → **A**
- "There's already a bundle that should own this" → **B**
- "I just need other things to connect to it; don't manage it" → **C**

When unsure, ask what the user actually needs: *manage* the resource (change it, deploy updates, eventually destroy it) → A/B; only *connect* to it → C.
