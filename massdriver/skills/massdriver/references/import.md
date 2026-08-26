# Importing Existing Cloud Resources

Bringing infrastructure that already exists — created by hand, by another IaC tool, or in
another account — under Massdriver. Read the path you need; don't read the whole file.

**Not to be confused with `mass bundle import`**, which scans a bundle's IaC for variables not
yet exposed as Massdriver params. Unrelated to this document.

## The Three Paths

| Path | What it does | Massdriver manages it? |
|------|--------------|------------------------|
| **A — New bundle** | Author a new reusable bundle, publish it, add it as a component, then import the live resource into that instance's state | Yes (full IaC lifecycle) |
| **B — Existing bundle** | Reuse a published bundle, pick/create an undeployed instance, import into its state | Yes (full IaC lifecycle) |
| **C — Register resource only** | Create an `EXTERNAL` resource so other components can connect to it | No — reference only |

A and B hand Massdriver the ability to change and eventually destroy the resource. C only makes
it referenceable on the canvas. If the user is unsure, ask: *manage* it (change/deploy/destroy)
→ A or B; only let components *connect* to it → C.

## Why not `import {}` blocks

A bundle is a reusable module deployed as many instances. An `import {}` block hardcodes one
cloud resource ID into bundle source, so every instance of that bundle would try to adopt the
same resource. **Never add `import {}` blocks to a bundle.** Adopt state with the imperative
`tofu import` command, pointed at one specific instance's state.

## Tooling for this workflow

- **MCP** — everything on the control plane: `get_viewer`, `get_project`, `get_environment`,
  `add_component`, `get_instance`, `update_instance`, `create_deployment`,
  `get_deployment_logs`, `set_environment_default`, `orphan_instance`.
- **CLI** — filesystem-bound work only: `mass bundle build|lint|new|publish|pull`,
  `mass resource-type get|list`, `mass resource create`.
- **Bash `tofu`** — the local state write (`tofu init`, `tofu import`, `tofu state list`).
  This is the one step no Massdriver tool performs for you.

---

## The State Import Procedure (Paths A and B)

Both bundle paths converge here. **The bundle must be published AND an instance must exist
first** — state is per-instance, so there is nothing to import into until then.

### Step 0: Safety gate — the hook does not cover this

The plugin's safety hook inspects `mass` CLI commands and MCP tool calls. `tofu import` is
plain Bash, so **nothing blocks you from writing to a production instance's state.** Before
importing into any instance whose environment segment looks like production, state the target
instance slug and get explicit user confirmation. Writing state is not a cloud mutation, but a
wrong-instance import is a mess to unwind.

### Step 1: Confirm the bundle is on Massdriver-managed state

Look at the bundle's `src/` for a `terraform { backend ... }` block:

- **No backend block** (the normal case — Massdriver's provisioner supplies state config): fine.
- **Empty `http` backend** (`terraform { backend "http" {} }`): fine.
- **Any other backend** (`s3`, `gcs`, `azurerm`, or an `http` backend with arguments): the
  bundle is NOT on Massdriver-managed state. Stop and tell the user — import cannot proceed
  until state lives on Massdriver.

### Step 2: Credentials for the state backend

The HTTP state backend authenticates with your **organization slug** and an **API key /
service account token**:

```bash
export TF_HTTP_USERNAME="$MASSDRIVER_ORGANIZATION_ID"   # organization slug
export TF_HTTP_PASSWORD="$MASSDRIVER_API_KEY"           # service account token
```

**NEVER read `~/.config/massdriver/config.yaml`** — it holds API keys for every configured
profile. If those two variables are already exported in the shell, reference them as above and
never echo their values. If they are not set (profile-based auth), ask the user to export them
for this session; do not go looking for them. `get_viewer` confirms which organization the MCP
server is authenticated to if you need to check the slug.

### Step 3: Get the instance's state URL

Call `get_instance` on the target instance. Its `statePaths` array gives one entry per bundle
step, each with `stepName` (the step key from `massdriver.yaml`, commonly `src`) and
`stateUrl` — the exact URL for that step's state. Use `stateUrl` verbatim; do not hand-build it.

```bash
export TF_HTTP_ADDRESS="<stateUrl for the step you're importing into>"
export TF_HTTP_LOCK_ADDRESS="$TF_HTTP_ADDRESS"
export TF_HTTP_UNLOCK_ADDRESS="$TF_HTTP_ADDRESS"
```

For a multi-step bundle, import each resource into the state of the step whose IaC declares it.

### Step 4: Select the http backend locally

`TF_HTTP_*` only applies when the http backend is actually selected. If the bundle has no
backend block, write a **throwaway** one in the step directory:

```bash
cd bundles/<bundle>/src
echo 'terraform {
  backend "http" {}
}' > backend_import.tf
```

Delete `backend_import.tf` when the import is done, and **never publish it** — the provisioner
supplies its own state configuration.

### Step 5: Give the provider enough config to read the resource

`tofu import` runs locally, so the provider has to authenticate for real. Bundle provider blocks
read credentials from a connection variable (e.g. `var.aws_authentication.arn`), which is empty
on your machine. Build a throwaway variables file:

1. `mass bundle build` to generate `_massdriver_variables.tf`.
2. Get the params: `get_instance` returns the instance's `params`.
3. Get the credential: read the environment's default cloud credential resource
   (`get_environment` → defaults). `export_resource` returns its payload including the role ARN
   — it returns **unmasked secrets**, so confirm with the user before calling it and never echo
   the result into the transcript.
4. Write `import.auto.tfvars.json` in the step directory with `md_metadata`, the required
   params, and the `<platform>_authentication` object. This file is throwaway — delete it after
   the import and never publish or commit it.
5. Your shell also needs ambient cloud credentials able to assume that role (e.g. `AWS_PROFILE`).

If assembling this is more trouble than it's worth for a one-off, say so and ask the user
whether they'd rather run the import commands themselves with their own credentials.

### Step 6: Import, then plan through Massdriver

```bash
tofu init
tofu import <resource.address> <cloud-provider-id>   # once per resource
tofu state list                                      # verify what landed in state
```

Then verify the config matches reality by planning **in Massdriver's provisioner**:

- Call `create_deployment` with `action: PLAN`, the instance's params, and a message. On a
  never-deployed instance this is the only option — `plan_deployment` replays an *existing*
  deployment's params and there isn't one yet.
- Read the result with `get_deployment_logs` (`follow: true`).
- The goal is a plan with **no changes**.

**Never run `tofu plan` locally.** The provisioner has the correct credentials, the run is
audited, and compliance tooling only executes there. `PLAN` deployments are exempt from the
hook's production block precisely because they cannot change anything.

### Step 7: Loop until the plan is clean

If the plan proposes changes, the HCL doesn't match the live resource. Per iteration:

1. Fix the HCL.
2. `mass bundle publish --development` (the platform cannot see your filesystem).
3. `update_instance` with version `latest+dev` so the instance resolves the release you just
   published — otherwise the next plan runs the OLD version.
4. `create_deployment` (`action: PLAN`) + `get_deployment_logs follow:true`.

**If the plan proposes destroying or replacing an imported resource, STOP.** That means the
config diverges from reality in a way an apply would act on. Reconcile the HCL; never deploy
while the plan is dirty.

**Path B caveat:** editing an existing bundle changes every instance using it. Prompt the user
before touching bundle source.

### Step 8: Clean up and hand off

Delete `backend_import.tf` and `import.auto.tfvars.json`. The instance now has real state and a
clean plan; the actual `PROVISION` deploy is a separate, human-authorized decision.

### Recovering from a bad import

- **Wrong resource imported**: `tofu state rm <resource.address>`, then re-import correctly.
- **State lock stuck** (an interrupted run): `orphan_instance` can clear state locks, but it
  also resets the instance to `INITIALIZED`. Confirm with the user first.
- **Import fails on provider auth**: that's Step 5, not a Massdriver problem. Report the exact
  provider error and ask the user how they'd like to supply credentials.

---

## Path A: New Bundle

1. **Author the bundle** using the normal bundle-development guidance in
   [SKILL.md](../SKILL.md) — fetch the platform resource type first
   (`mass resource-type get <platform>`), write `massdriver.yaml` and `src/`.
   - **Scope the bundle to the resource plus its immediate dependencies.** Importing a database
     means also covering its security group, parameter group, and subnet group — not just the
     DB. Match the HCL to what actually exists, or the plan will never come clean.
   - When it's ambiguous whether a neighbouring resource belongs in this bundle, ask the user.
2. **Ensure the OCI repository exists and is granted** — `get_oci_repo` with the bundle name;
   if absent, `create_oci_repo` (`artifact_type: BUNDLE`), then check `list_oci_repo_grants`
   covers the target project and `create_oci_repo_grant` if not. Without the grant,
   `add_component` fails.
3. **Publish** (CLI): `mass bundle publish --development`.
4. **Add to the blueprint** (MCP): `add_component`. Every environment in the project now has an
   instance; the one you want is `<project>-<env>-<component>`.
5. **Pin the development channel** (MCP): `update_instance` with version `latest+dev`.
6. Run **The State Import Procedure** against that (undeployed) instance.

## Path B: Existing Bundle

1. **Identify the bundle** and pull its source if you don't have it: `mass bundle pull <name>`.
   Confirm the backend (Procedure Step 1).
2. **Establish the target instance.** Ask the user whether to add the component to a new
   project/environment or import into an existing **undeployed** instance. Importing into an
   already-provisioned instance would collide with state it already owns — don't, unless the
   user explicitly confirms that's what they want.
3. **Pin the development channel** if you'll be republishing: `update_instance`, `latest+dev`.
4. Run **The State Import Procedure**, prompting before any bundle edits.

## Path C: Register Resource Only

Creates a Massdriver resource with origin `EXTERNAL`. Massdriver stores the payload and lets
other components connect to it; it will never deploy, change, or destroy it. No IaC, no state,
no instance.

1. **Pick the resource type** and read its schema:
   ```bash
   mass resource-type list
   mass resource-type get <resource-type>
   ```
   Resource types can ship their own import instructions (the `instructions` field on
   `ResourceType`, one entry per workflow — CLI, cloud console, etc.). If the type has them,
   follow them over the generic steps here.
2. **Discover the live values** with the cloud CLI (`aws … describe`, `gcloud … describe`,
   `az … show`) and build a payload that validates against the schema. Write it to a file:
   ```bash
   cat > /tmp/resource.json <<'JSON'
   { "infrastructure": { "arn": "…" }, "aws": { "region": "us-west-2" } }
   JSON
   ```
3. **Create the resource:**
   ```bash
   mass resource create -n "<name>" -t <resource-type> -f /tmp/resource.json
   ```
   The output includes the new resource ID. If the CLI can't express what you need (org
   scoping, for instance), the `createResource` GraphQL mutation is the fallback — it takes
   `organizationId`, `resourceTypeId`, and `input: { name, payload }`, and requires the
   `resource:import` permission. See [graphql.md](./graphql.md).
4. **Optionally make it an environment default** (MCP) so components connect to it without an
   explicit link: `set_environment_default`. Ask first — this changes what every instance in
   that environment connects to.
5. **Tell the user plainly**: this resource is `EXTERNAL`. Massdriver will not manage its
   lifecycle. Nothing will deploy or destroy it.

---

## Reporting

Whatever the path, close by telling the user:

- Which path was taken and why.
- What now exists — bundle path, component id, instance slug, or resource ID.
- Import status: which resources landed in state, and confirmation that the `PLAN` deployment
  came back with no changes.
- What's left for a human: deploying the instance, importing into additional
  environments/instances, publishing stable. Production deploys and stable publishes are
  human-authorized and hook-blocked — say so rather than attempting them.
