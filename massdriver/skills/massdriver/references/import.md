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

## Dependencies that belong to another bundle

Real infrastructure has dependencies, and some of them are not part of the thing you are
importing. A database sits in a network. If that network is not already in Massdriver — as a
bundle's output or as an imported resource — the import is blocked, and both obvious ways out are
wrong:

- **Network values as bundle params.** One line, and the plan goes clean. But the network's
  identity becomes deploy-time config instead of a modeled dependency: nothing on the canvas
  shows the relationship, nothing stops the value drifting, and every new environment retypes it.
- **The network inside the bundle.** Worse. The bundle claims a resource it did not create and
  that other things depend on; destroying the instance would try to destroy the network.

### Where the line is

Two questions, cheapest first:

1. **Does anything else already use it?** If yes it cannot go in this bundle — destroying the
   bundle would break the others.
2. **Should destroying this resource destroy it?** A parameter group, a subnet group, a security
   group created for this database: yes, they die with it, they belong in the bundle. A network,
   a DNS zone, a KMS key shared across services, a cluster: no. Those are connections.

This generalizes past networks — a shared KMS key and an existing cluster have the same shape and
are less obvious.

### What to do

**Stop and ask the user.** Never decide this silently. Name the dependency, say which bundle it
would belong to, and offer the two real options:

- **Halt** — author or import the dependency properly first, then come back.
- **Register the dependency as an imported resource** (Path C) and continue. It fills the
  bundle's connection slot and unblocks the main import; a second import can bring the dependency
  under management later.

If they continue, the imported resource must exist and be wired **before Step 5** — that step
builds `import.auto.tfvars.json` from the instance's params *and* its connections, so an unfilled
slot surfaces at Step 6 as a provider error that looks unrelated. Wire it with
`set_remote_reference` (one instance's slot; `resource_id` is the imported resource's UUID) or
`set_environment_default` (every instance in the environment).

**Path B presents differently.** The bundle already declares the connection, so the symptom is an
empty slot with nothing to fill it rather than a scoping decision. Same resolution.

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

### No release channels, no deploys

Normal bundle development pins a release channel (`latest+dev`, `~1+dev`) so an instance picks
up each new publish. **Import must not.** A release channel makes the platform run a full deploy
(`tofu apply`) on every publish — against infrastructure that already exists and may be
production. An apply before the plan is clean can destroy or duplicate real resources.

Pin **exact dev releases only**. `mass bundle publish --development` emits one per publish,
timestamped: `1.2.3+dev-20260423T120000`. The timestamped form is a specific immutable release
and is safe; the bare `+dev` suffix is the channel and is not. Re-pin explicitly after each
publish — an exact pin never floats, so no publish can trigger anything on its own.

The only deployment action in this whole procedure is `create_deployment` with `action: PLAN`.
Nothing here provisions.

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

### Step 2: Resolve the state backend credentials

The backend authenticates with the **organization slug** (`TF_HTTP_USERNAME`) and an **API key /
service account token** (`TF_HTTP_PASSWORD`). Two sources:

- **API-key auth** — `$MASSDRIVER_ORGANIZATION_ID` and `$MASSDRIVER_API_KEY` are in the
  environment. Test with `[ -n "${MASSDRIVER_API_KEY:-}" ]`; never print them. `get_viewer`
  confirms the org the MCP server is authenticated to.
- **Profile auth** — neither is set. Pipe `mass config get -o json --show-secrets | jq -r .apiKey`
  straight into the variable inside the Step 6 block. Never run it standalone — the key would
  land in the transcript. May need a `mass config get:*` allowlist rule.

**NEVER read `~/.config/massdriver/config.yaml` directly** — it holds keys for every profile.

If neither resolves, ask the user to restart Claude Code with both variables exported; the
environment cannot be changed mid-session.

Gather the values here, do not export them. Exports do not survive between Bash calls, so every
`TF_HTTP_*` assignment shares one invocation with `tofu` in Step 6.

### Step 3: Get the instance's state URL

Call `get_instance` on the target instance. Its `statePaths` array gives one entry per bundle
step, each with `stepName` (the step key from `massdriver.yaml`, commonly `src`) and
`stateUrl` — the exact URL for that step's state. Use `stateUrl` verbatim; do not hand-build it.

Note the value for Step 6 — do not export it here. For a multi-step bundle, import each
resource into the state of the step whose IaC declares it.

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

`tofu import` runs locally, so the provider must authenticate for real — and the identity
Massdriver provisions with is frequently one you **cannot** reproduce on your machine by design.
Every cloud has some form of delegated identity scoped to the provisioner (assumed roles,
service-account impersonation, workload identity federation), and the point of it is that it is
not usable from a laptop. A failure here is usually that design working, not a bug to engineer
around.

You do not need Massdriver's credential. You need **any** credential of the user's that can read
the resource. Try in order, stop at the first that works:

1. **Use what is already in the shell.** Most providers resolve an ambient credential with no
   configuration — an environment variable, a CLI login, a key or service-account file the user
   already has. If their default credential can read the resource, you need nothing else.
2. **Initialize the provider from the user's local credential.** Bundle provider blocks read from
   a connection variable the platform populates (`var.<platform>_authentication.*`), which is
   empty on your machine. Comment that block out and add a plain one beside it that uses the
   provider's default credential resolution — or the key, access key, or service-account file the
   user points you at. This is a **temporary local edit**; see the warning below.
3. **Reproduce Massdriver's identity locally** — only if the user confirms they hold it and can
   use it from their machine. `get_environment` → defaults identifies the credential resource and
   `export_resource` returns its payload. That payload contains **unmasked secrets**, so confirm
   before calling it and never echo the result. Then `mass bundle build` and write a throwaway
   `import.auto.tfvars.json` in the step directory with `md_metadata`, the required params, and
   the `<platform>_authentication` object.

**If none of those work, STOP and ask the user how they want to proceed** — most usefully, ask
which credential they normally use for this account, project or subscription. Do not get
creative: no probing for credential files, no enumerating profiles, no trying other identities,
no inventing an authentication path. Report the exact provider error and offer to hand them the
`tofu import` command to run with their own credentials.

> **Revert every provider edit before ANY `mass bundle publish`** — including the republish loop
> in Step 7, not just the cleanup in Step 8. A provider block rewritten for local credentials
> that reaches the platform breaks every instance of the bundle. `backend_import.tf` and
> `import.auto.tfvars.json` are throwaway on the same terms: never committed, never published.

### Step 6: Import, then plan through Massdriver

One invocation — the exports do not survive into a second Bash call, and any later `tofu`
command needs the same preamble repeated:

```bash
cd bundles/<bundle>/src

export TF_HTTP_USERNAME="$MASSDRIVER_ORGANIZATION_ID"  # profile auth: $(mass config get -o json | jq -r .organizationId)
export TF_HTTP_PASSWORD="$MASSDRIVER_API_KEY"          # profile auth: $(mass config get -o json --show-secrets | jq -r .apiKey)
export TF_HTTP_ADDRESS="<stateUrl from Step 3>"
export TF_HTTP_LOCK_ADDRESS="$TF_HTTP_ADDRESS"
export TF_HTTP_UNLOCK_ADDRESS="$TF_HTTP_ADDRESS"

tofu init
tofu import <resource.address> <cloud-provider-id>   # repeat per resource, same call
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
2. **Restore the real provider block** if Step 5 changed it, and confirm `backend_import.tf` and
   `import.auto.tfvars.json` are not staged for publish.
3. `mass bundle publish --development` (the platform cannot see your filesystem).
4. `update_instance` with the **exact dev release** that publish just emitted (e.g.
   `1.2.3+dev-20260423T120000`) so the next plan runs the code you just fixed. Never a channel
   constraint — see *No release channels, no deploys*.
5. `create_deployment` (`action: PLAN`) + `get_deployment_logs follow:true`.

**If the plan proposes destroying or replacing an imported resource, STOP.** That means the
config diverges from reality in a way an apply would act on. Reconcile the HCL; never deploy
while the plan is dirty.

### Step 8: Clean up and hand off

Delete `backend_import.tf` and `import.auto.tfvars.json`, and restore the original provider
block if Step 5 changed it. Diff the bundle against what you started with — nothing from the
local import should survive. The instance now has real state and a clean plan; the actual
`PROVISION` deploy is a separate, human-authorized decision.

**Then check what this import made obsolete.** `list_resources` with `origin: IMPORTED`, scoped
to the environment. If one of them represents the infrastructure you just brought into a bundle,
it is now redundant — there is no reason to keep an imported resource once a provisioned one
exists for the same thing.

**Report it, do not act on it.** The replacement cannot happen yet: the bundle's resource does
not exist until the user completes the import with a full deploy, which is theirs to run. And
re-pointing consumers is not part of this flow — `set_remote_reference` refuses an instance in
`PROVISIONED` status, so anything already deployed against the imported resource needs separate,
deliberate work. Name the superseded resource and what retiring it would involve.

### Recovering from a bad import

- **Wrong resource imported**: `tofu state rm <resource.address>`, then re-import correctly.
- **State lock stuck** (an interrupted run): `orphan_instance` can clear state locks, but it
  also resets the instance to `INITIALIZED`. Confirm with the user first.
- **Provider errors about a missing network, cluster or other upstream**: usually an unfilled
  connection slot, not a credential problem. See *Dependencies that belong to another bundle*.
- **Import fails on provider auth**: expected when Massdriver's identity is scoped to the
  provisioner. Work the Step 5 ladder, then stop and ask. Do not improvise a credential path.

---

## Path A: New Bundle

1. **Author the bundle** using the normal bundle-development guidance in
   [SKILL.md](../SKILL.md) — fetch the platform resource type first
   (`mass resource-type get <platform>`), write `massdriver.yaml` and `src/`.
   - **Scope the bundle to the resource plus the dependencies it owns.** Importing a database
     means also covering its security group, parameter group, and subnet group — not just the
     DB. Match the HCL to what actually exists, or the plan will never come clean.
   - **That list has a boundary**: the subnet group belongs in the bundle, the network it points
     at does not. See *Dependencies that belong to another bundle* — getting this wrong is not a
     style question, it hands the bundle the power to destroy shared infrastructure.
2. **Ensure the OCI repository exists and is granted** — `get_oci_repo` with the bundle name;
   if absent, `create_oci_repo` (`artifact_type: BUNDLE`), then check `list_oci_repo_grants`
   covers the target project and `create_oci_repo_grant` if not. Without the grant,
   `add_component` fails.
3. **Publish** (CLI): `mass bundle publish --development`.
4. **Add to the blueprint** (MCP): `add_component`. Every environment in the project now has an
   instance; the one you want is `<project>-<env>-<component>`.
5. **Pin the exact dev release** (MCP): `update_instance` with the version `mass bundle publish`
   emitted, timestamp and all. Never `latest+dev` — see *No release channels, no deploys*.
6. Run **The State Import Procedure** against that (undeployed) instance.

## Path B: Existing Bundle

1. **Identify the bundle** and pull its source if you don't have it: `mass bundle pull <name>`.
   Confirm the backend (Procedure Step 1).
2. **Establish the target instance.** Ask the user whether to add the component to a new
   project/environment or import into an existing **undeployed** instance. Importing into an
   already-provisioned instance would collide with state it already owns — don't, unless the
   user explicitly confirms that's what they want.
3. **Pin the exact dev release** if you'll be republishing: `update_instance` with the
   timestamped version, never a release channel — see *No release channels, no deploys*.
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
   `az … show`) and build a payload that validates against the schema — the schema decides the
   shape, not this example. Write it to a file:
   ```bash
   cat > /tmp/resource.json <<'JSON'
   { "infrastructure": { "<id-field>": "…" }, "<cloud>": { "region": "…" } }
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

