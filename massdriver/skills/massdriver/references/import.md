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
| **C — Register resource only** | Create an imported resource so other components can connect to it | No — reference only |

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
importing. An example: a database may require a network. If the network is not already in 
Massdriver — as a bundle's output or as an imported resource — the import is blocked, and both 
obvious ways out are wrong:

- **The dependency's values as bundle params.** This makes the dependency's identity a 
  deploy-time config instead of a modeled dependency: nothing on the canvas or in the platform
  shows the relationship, nothing stops the value drifting, and every new environment retypes it.
- **The dependency inside the bundle.** Worse. The bundle claims ownership of a resource it did 
  not create and that other things may depend on; destroying the instance would destroy the 
  dependency.

### Where the line is

Two questions, cheapest first:

1. **Does anything else use it?** If yes it cannot go in this bundle — destroying the bundle
   would break the others.
2. **Do the resources share a lifecycle?** If destroying the imported resource should also
   destroy it — it exists only to serve the imported resource — it belongs in the bundle. If it
   would outlive the imported resource, it is a connection.

### Ask once, before anything exists

When you find the resource, also inventory what it references and what references it or was
created alongside it. Sort each into the bundle, a connection, or **left unmanaged** — a valid
choice when the user doesn't want Massdriver to own or model it, as long as you name it.

Put every question to the user in one round, before creating anything in Massdriver: scope, where
the instance goes, the bundle name, the output resource type, and whether the target environment
already has a usable credential for the resource's cloud (if not, the user can create one while
you work).

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

## Settings the cloud won't change

Some settings can't be changed on a live resource — the provider replaces the resource instead
(`ForceNew` in the provider's schema). Every param that feeds one is immutable ([SKILL.md](../SKILL.md)
Critical Rule 8), and import sets it from the live value.

Names are the case you will commonly hit. Bundles generally name resources from
`md_metadata.name_prefix`, which rarely equals the name of a resource that already exists.
Choosing project, environment and component slugs cannot fix this. The bundle needs a
**name-override param** for each such name: immutable, empty by default, and an empty value falls
back to `name_prefix` so ordinary instances behave as before. Import sets it to the live name.

On Path A, write these params in from the start. On Path B, a bundle without them needs an edit —
ask first (see Path B).

## Values the cloud can't return

Build the **import params** from what you read from the cloud: every param the live resource
determines, filled without asking, even when a field looks sensitive. The exception is
write-only values — passwords, keys and tokens the API accepts but never returns. Those are the
only params an import can't produce. For each one, ask the user which way to supply it. On Path B
the bundle has already decided: a param can go either way, an `app.secrets` entry only as a secret.

- **Hand it to Claude** — for a value that isn't really secret, or when the user accepts the
  exposure. It goes in the PLAN and proposal params; say that it lands in the transcript. Auto
  mode may deny that call as credential leakage even after the user agreed. If it does, stop and
  have the user retry it from `/permissions` → *Recently denied*. Do not resend it another way.
- **Instance secret** — for a value that is actually sensitive. The agent never sees it:
  - Declare it under `app.secrets` in `massdriver.yaml` with an uppercase name
    (`<SECRET_NAME>`, `required: true`).
  - Read it through Massdriver's `massdriver-bundle` module, which exposes the secrets the
    provisioner injects:
    ```hcl
    module "bundle" {
      source = "github.com/massdriver-cloud/terraform-modules//massdriver-bundle?ref=2a7f3df"
    }
    locals {
      secret_value = sensitive(module.bundle.secrets["<SECRET_NAME>"])
    }
    ```
    Wrap it in `sensitive()` — the module's `secrets` output is not marked sensitive. Index
    required secrets directly, so a missing one fails the plan; `try()` only for optional ones.
  - The user sets the value in the UI. Never call `set_instance_secret` with it. No tool shows
    whether a secret is set, so the PLAN is the check: a missing one fails on the index.

Never invent, reuse or rotate a write-only value without asking. Whichever way it arrives, the
plan shows the attribute as an in-place update — import cannot record a value the cloud never
returns.

---

## The State Import Procedure (Paths A and B)

Both bundle paths converge here. **The bundle must be published AND an instance must exist
first** — state is per-instance, so there is nothing to import into until then.

### No release channels, no deploys

Normal bundle development pins a release channel (`latest+dev`, `~1+dev`) so an instance picks
up each new publish. **Import must not.** A release channel makes the platform run a full deploy
(`tofu apply`) on every publish — against infrastructure that already exists and may be
production. An apply before the plan is clean can destroy or duplicate real resources.

Pin **exact dev releases only**. `mass bundle publish --development` emits one per publish:
`<version>-dev.<UTC timestamp>`, e.g. `0.0.1-dev.20260929T000749Z`. That is a specific
immutable release and is safe; `latest+dev` / `~1+dev` are channels and are not. Re-pin
explicitly after each publish — an exact pin never floats, so no publish can trigger anything on
its own.

The deployment actions in this procedure are `create_deployment` with `action: PLAN`, and one
`propose_deployment` at the end (Step 8) that a human approves. Nothing here provisions.

### Step 0: Safety gate — the hook does not cover this

The plugin's safety hook inspects `mass` CLI commands and MCP tool calls. `tofu import` is
plain Bash, so **nothing blocks you from writing to a production instance's state.** Before
importing into any instance whose environment segment looks like production, state the target
instance slug and get explicit user confirmation. Writing state is not a cloud mutation, but a
wrong-instance import is a mess to unwind.

Importing into production is supported only while the instance is **undeployed** — Path B never
imports into a provisioned instance without the user's explicit say-so. The hook can't see
instance status, so on production every configuration call (pinning, secrets, references,
defaults, grants) and the final proposal prompts the user, even in auto mode. Say which instance
and why before each one. Provisioning and decommissioning production stay blocked.

### Step 1: Confirm the bundle is on Massdriver-managed state

Look at the bundle's `src/` for a `terraform { backend ... }` block:

- **No backend block** (the normal case — Massdriver's provisioner supplies state config): fine.
- **Empty `http` backend** (`terraform { backend "http" {} }`): fine.
- **Any other backend** (any other backend type, or an `http` backend with arguments): the
  bundle is NOT on Massdriver-managed state. Stop and tell the user — import cannot proceed
  until state lives on Massdriver.

### Step 2: Resolve the state backend credentials

The backend authenticates with the **organization slug** (`TF_HTTP_USERNAME`) and an **API key /
service account token** (`TF_HTTP_PASSWORD`). Two sources:

- **API-key auth** — `$MASSDRIVER_ORGANIZATION_ID` and `$MASSDRIVER_API_KEY` are in the
  environment. Test with `[ -n "${MASSDRIVER_API_KEY:-}" ]`; never print them. `get_viewer`
  confirms the org the MCP server is authenticated to.
- **Profile auth** — neither is set. The slug is the organization `get_viewer` returns. Pipe
  `mass config get -o json --show-secrets | jq -r .api_key` straight into the variable inside
  the Step 6 block. Never run it standalone — the key would
  land in the transcript. The plugin's safety hook always asks the user to approve this
  command, even in auto mode, so tell them what the prompt is for before you run it. Keep it
  inline in the Bash command, never inside a script file — the hook only sees the command text.
  If the user declines, fall back to the restart below.

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

**Check the connection slots in the same response**, including the cloud credential. Every
required slot must be filled before the PLAN, and a new project or environment usually has
nothing bound. Imported resources or provisioned resources created by an instance in
another environment can be set as a default for the entire environment (common for credentials)
with `set_environment_default`, or can be set per-instance with `set_remote_reference`. Using
an imported resource or a provisioned resource from another environment requires a
`resource:export` grant to exist granting permission to the current environment, before either
`set_environment_default` or `set_remote_reference` will accept it. If a grant
doesn't exist, create one (`create_resource_grant`) and scope it with both the `md-project` and
`md-environment` condition keys to only allow this specific environment. `md-environment` takes
the environment's own id (`dev`), not the full `<project>-<env>` slug. If unsure whether to use
environment default or remote reference, ask the user which they prefer.

### Step 4: Select the http backend locally

Copy the bundle aside first — Step 6 diffs against that copy to prove nothing from the local
import survives.

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

You may not need Massdriver's credential. You need **any** credential of the user's that can read
the resource. Try in order, stop at the first that works:

1. **Use what is already in the shell.** Most providers resolve an ambient credential with no
   configuration — an environment variable, a CLI login, a key or service-account file the user
   already has. If their default credential can read the resource, you need nothing else.
2. **Initialize the provider from the user's local credential.** Bundle provider blocks read from
   the credential connection, which is empty on your machine. Comment that block out and add a
   plain one beside it that uses the user's credential. This is a **temporary local edit** to
   bundle source; see the warning below.
3. **Reproduce Massdriver's identity locally** — only if the user confirms they hold it and can
   use it from their machine. `get_environment` → defaults identifies the credential resource and
   `export_resource` returns its payload. That payload contains **unmasked secrets**, so confirm
   before calling it and never echo the result, then put it in `import.auto.tfvars.json` below.

**If none of those work, STOP and ask the user how they want to proceed** — most usefully, ask
which credential they normally use for this account, project or subscription. Do not get
creative: no probing for credential files, no enumerating profiles, no trying other identities,
no inventing an authentication path. Report the exact provider error and offer to hand them the
`tofu import` command to run with their own credentials.

**Every variable without a default needs a value**, whichever rung you're on. Run
`mass bundle build`, then write a throwaway `import.auto.tfvars.json` in the step directory with
`md_metadata`, the import params, and the credential object, matching the types in
`_massdriver_variables.tf` — `md_metadata` is a full object there, and a partial one fails type
checking. If the provider doesn't read the credential, placeholder strings are
fine; never put a real secret there.

> **Nothing from this step reaches the platform.** The commented-out provider block, the local
> one beside it, `backend_import.tf`, `import.auto.tfvars.json` and any other local edit are
> throwaway: never committed, never published. A provider block rewritten for local credentials
> that reaches the platform breaks every instance of the bundle.

### Step 6: Import, clean up, then plan through Massdriver

One invocation — the exports do not survive into a second Bash call, and any later `tofu`
command needs the same preamble repeated:

```bash
cd bundles/<bundle>/src

export TF_HTTP_USERNAME="$MASSDRIVER_ORGANIZATION_ID"  # profile auth: the get_viewer org slug
export TF_HTTP_PASSWORD="$MASSDRIVER_API_KEY"          # profile auth: $(mass config get -o json --show-secrets | jq -r .api_key)
export TF_HTTP_ADDRESS="<stateUrl from Step 3>"
export TF_HTTP_LOCK_ADDRESS="$TF_HTTP_ADDRESS"
export TF_HTTP_UNLOCK_ADDRESS="$TF_HTTP_ADDRESS"

tofu init -input=false
tofu import -input=false <resource.address> <cloud-provider-id>   # repeat per resource, same call
tofu state list                                                   # verify what landed in state
```

**Clean up as soon as `tofu state list` shows every resource.** The state now lives in the
backend and the PLAN runs from the published bundle, so nothing local is needed again. Restore
the original provider block, delete `backend_import.tf`, `import.auto.tfvars.json`, `.terraform/`
and the lock file `tofu init` created, and diff the bundle against the copy from Step 4 — nothing
from the local import may survive.

Then verify the config matches reality by planning **in Massdriver's provisioner**:

- Call `create_deployment` with `action: PLAN`, the import params (see *Values the cloud can't
  return*), and a message. On a never-deployed instance this is the only option —
  `plan_deployment` replays an *existing* deployment's params and there isn't one yet.
- **A PLAN does not save its params.** Only a deployment saves an instance's config, so the
  instance's form still holds the bundle defaults. A Deploy from the form would apply those
  defaults, not the import params — and on an imported resource that can mean replace.
- Read the result with `get_deployment_logs` (`follow: true`).

**A clean plan** does **NOT** create, destroy or replace any of the imported resources. The only
in-place updates it may show are write-only attributes (see *Values the cloud can't return*) and
Massdriver's default tags on resources that were untagged. Creating the bundle's own
`massdriver_resource` outputs is expected on the first deploy. Anything else means the HCL or the
import params don't match the live resource. Tell the user which in-place updates the plan
shows before you propose.

**Checkov output prints plan values in plaintext**, including sensitive attributes of any
resource it flags. Never quote Checkov blocks. If a secret sits on a flagged resource, tell the
user it is exposed to anyone who can read the deployment logs and should be rotated after the
deploy. Checkov failures don't block an import — they describe how the resource was built — but
list them for the user before they approve. Handle them later under
[compliance.md](./compliance.md).

**Never run `tofu plan` locally.** The provisioner has the correct credentials, the run is
audited, and compliance tooling only executes there. `PLAN` deployments are exempt from the
hook's production block precisely because they cannot change anything.

### Step 7: Loop until the plan is clean

If the plan isn't clean, the HCL or the import params don't match the live resource. Fix the
params and re-plan, or per HCL iteration:

1. Fix the HCL. The state is already imported — nothing local needs recreating.
2. `mass bundle publish --development` (the platform cannot see your filesystem).
3. `update_instance` with the **exact dev release** that publish just emitted, so the next plan
   runs the code you just fixed — see *No release channels, no deploys*.
4. `create_deployment` (`action: PLAN`) + `get_deployment_logs follow:true`.

**If the plan proposes destroying or replacing an imported resource, STOP.** That means the
config diverges from reality in a way an apply would act on. Reconcile the HCL; never deploy
while the plan is dirty.

**Some in-place diffs no config can match** — the provider normalizes or rejects the value the
cloud stored. Name each one to the user with what an apply would actually do, and let them
choose: accept it as part of the plan, suppress it with `lifecycle { ignore_changes }`, or stop.
Never suppress a diff on your own; an ignore in shared bundle source hides future drift too.

### Step 8: Hand off

The instance now has real state and a clean plan; the `PROVISION` deploy is a separate,
human-authorized decision — hand it off as a proposal.

**Propose the deployment with the import params.** `propose_deployment` with `action:
PROVISION`, the exact params from the last clean PLAN, and a message. The proposal is what
carries the import params to the platform; nothing else does. Then `plan_deployment` on the
proposal's id and confirm it is the same clean plan. Tell the user to review that plan and
approve or reject the proposal in the UI — and **not to Deploy from the instance form**, which
still holds the defaults until the proposal is approved. Never approve it yourself.

**Then check what this import made obsolete.** `list_resources` with `origin: IMPORTED` and the
bundle's output type at its version — imported resources belong to the organization, not an
environment, so don't filter by environment. If one of them represents the infrastructure you
just brought into a bundle, it is now redundant — there is no reason to keep an imported resource
once a provisioned one exists for the same thing.

**Report it, do not act on it.** The replacement cannot happen yet: the bundle's resource does
not exist until the user approves the proposed deployment. Name the superseded resource and
every instance bound to it. Once the deploy is done, and only when the user asks, retire it:
move each consumer onto the provisioned resource, then delete the imported one.

- **Same environment as the new instance:** replace the consumer's remote reference with a
  `link_components` link from the new component.
- **Another environment or project:** a link can't cross environments. Keep the binding's
  form — remote reference or environment default — but point it at the provisioned resource
  (which needs a `resource:export` grant, Step 3).

Plan each consumer with its saved params; it should show no changes.

### Recovering from a bad import

- **Wrong resource imported**: `tofu state rm <resource.address>`, then re-import correctly.
- **State lock stuck** (an interrupted run): `orphan_instance` can clear state locks, but it
  also resets the instance to `INITIALIZED`. Confirm with the user first.
- **Provider errors about a missing upstream resource**: usually an unfilled
  connection slot, not a credential problem. See *Dependencies that belong to another bundle*.
- **Import fails on provider auth**: expected when Massdriver's identity is scoped to the
  provisioner. Work the Step 5 ladder, then stop and ask. Do not improvise a credential path.

---

## Path A: New Bundle

1. **Author the bundle** using the normal bundle-development guidance in
   [SKILL.md](../SKILL.md) — fetch the platform resource type first
   (`mass resource-type get <platform>`), write `massdriver.yaml` and `src/`.
   - **Scope the bundle to the resource plus what shares its lifecycle** — everything that
     exists only to serve it, not just the resource itself. Match the HCL to what actually
     exists, or the plan will never come clean.
   - **That scope has a boundary**: anything that would outlive the resource is a connection, not
     part of the bundle. See *Dependencies that belong to another bundle* — getting this wrong
     is not a style question, it hands the bundle the power to destroy shared infrastructure.
   - **Make every replace-forcing param immutable, and add name overrides** — see *Settings the
     cloud won't change*.
   - **Decide how each write-only value arrives** — a param or an `app.secrets` entry. See
     *Values the cloud can't return*.
   - **Choose the output resource type with the user.** Look for an existing type that fits
     (`list_oci_repos` with `artifact_type: RESOURCE_TYPE`, then `get_resource_type`). If one
     appears to match, ask whether to reuse it or author a new one; if none does, ask before
     authoring one. A new resource type is live for the whole organization as soon as it is
     published, and it needs its own OCI repo and a `version:` first (SKILL.md, *Publishing
     Reference*). It can't share a name with the bundle.
2. **Ensure the OCI repository exists and is granted** — `get_oci_repo` with the bundle name;
   if absent, `create_oci_repo` (`artifact_type: BUNDLE`), then check `list_oci_repo_grants`
   covers the target project and `create_oci_repo_grant` if not. Without the grant,
   `add_component` fails.
3. **Publish** (CLI): `mass bundle publish --development`.
4. **Add to the blueprint** (MCP): `add_component`. Every environment in the project now has an
   instance; the one you want is `<project>-<env>-<component>`.
5. **Pin the exact dev release** (MCP): `update_instance` with the version `mass bundle publish`
   emitted (`0.0.1-dev.20260929T000749Z`). Never `latest+dev` — see *No release channels, no
   deploys*.
6. Run **The State Import Procedure** against that (undeployed) instance.

## Path B: Existing Bundle

**Use the bundle as-is.** It is already published and other instances may already run it. The
goal is to fit the import to the bundle, not the bundle to one resource — reach for a bundle edit
only after the params can't express what the live resource actually looks like.

Sometimes they can't, and the plan will never come clean without a change. When that happens,
**stop and ask the user before touching bundle source**, and keep whatever you change backward
compatible with every existing instance:

- New params must be **optional, with defaults that preserve today's behavior**. A new required
  param breaks every instance whose saved params predate it.
- New connections must be optional too — a new required slot leaves existing instances unfilled.
- Don't rename or remove params, narrow a type, or add constraints that existing saved values
  would now fail.
- Don't change artifact outputs; downstream instances are connected to those fields.

Your `--development` publishes don't reach instances pinned to stable, so iterating is safe. The
compatibility bill comes due when someone publishes stable — a human decision, not yours. Say
plainly in the handoff that the bundle changed and what it would mean for existing instances.

1. **Identify the bundle** and pull its source if you don't have it: `mass bundle pull <name>`.
   Confirm the backend (Procedure Step 1).
2. **Establish the target instance.** Ask the user whether to add the component to a new
   project/environment or import into an existing **undeployed** instance. Importing into an
   already-provisioned instance would collide with state it already owns — don't, unless the
   user explicitly confirms that's what they want. A project the bundle's OCI repo isn't granted
   to needs a grant (`list_oci_repo_grants`, `create_oci_repo_grant`), or `add_component` fails.
3. **Pin an exact release** with `update_instance` — the release you pulled, or the dev release
   each republish emits. Never a release channel — see *No release channels, no deploys*.
4. Run **The State Import Procedure**, prompting before any bundle edits.

## Path C: Register Resource Only

Creates a Massdriver resource with origin `IMPORTED`, owned by the organization rather than an
environment. Massdriver stores the payload and lets other components connect to it; it will
never deploy, change, or destroy it. No IaC, no state, no instance.

1. **Pick the resource type** — `list_oci_repos` with `artifact_type: RESOURCE_TYPE` — and read
   its schema with `get_resource_type`.
   If none fits, ask before authoring one — it is live for the organization once published.

   Resource types can ship their own import instructions (the `instructions` field on
   `ResourceType`, one entry per workflow — CLI, cloud console, etc.). If the type has them,
   follow them over the generic steps here.
2. **Discover the live values** with the cloud's CLI or API and build a payload that validates
   against the schema — the schema decides the shape, not this example. Write it to a file:
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
5. **Tell the user plainly**: this resource is registered, not managed. Massdriver will not
   manage its lifecycle. Nothing will deploy or destroy it.

