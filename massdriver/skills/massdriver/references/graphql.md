# GraphQL v2 API Reference

Massdriver v2 exposes a GraphQL API at `https://api.massdriver.cloud/graphql/v2`. The full schema is at `https://api.massdriver.cloud/graphql/v2/schema.graphql`. Most mutations also publish JSON Schema and UI Schema documents at `/graphql/v2/inputs/<mutationName>.json` and `.ui.json` for form generation.

**Use the CLI first.** Almost everything you need for bundle development is now in `mass`. Use GraphQL only for operations the CLI doesn't cover, or when you need to query several related entities in one round-trip.

## What's only in GraphQL (no CLI verb)

| Operation | Mutation |
|---|---|
| Fork an environment from another | `forkEnvironment` |
| Delete an environment | `deleteEnvironment` |
| Clone a project's blueprint | `cloneProject` |
| Copy instance config between instances | `copyInstance` |
| Manage instance secrets | `setInstanceSecret`, `removeInstanceSecret` |
| Reset an instance's state | `orphanInstance` |
| Deployment approval flow | `proposeDeployment`, `approveDeployment`, `rejectDeployment`, `abortDeployment` |
| Manage remote resource references | `setRemoteReference`, `removeRemoteReference` |
| Set component canvas position | `setComponentPosition` |
| Remove env default by id | `removeEnvironmentDefault` |

## v1 → v2 cheat sheet

| v1 (legacy) | v2 |
|---|---|
| `configurePackage` | folded into `createDeployment(input.params)` — params travel with each deploy |
| `deployPackage` | `createDeployment(action: PROVISION)` |
| `decommissionPackage` | `createDeployment(action: DECOMMISSION)` |
| `decommissionEnvironment` | `deleteEnvironment` (after instances are decommissioned) |
| `copyPackage` | `copyInstance` |
| `setPackageVersion` | `updateInstance(input: {version, releaseStrategy})` |
| `createManifest` | `addComponent` |
| `linkManifests` | `linkComponents` |
| `forkEnvironment(copySecrets, copyEnvDefaults, copyRemoteReferences)` | `forkEnvironment(copyEnvironmentDefaults)`; per-instance secrets/refs via `copyInstance` |
| `package(...)` | `instance(...)` |
| `repos(...)` | `ociRepos(...)` and `bundles(...)` |
| `deploymentLogStream(...)` | `deploymentLogs(...)` |
| `artifactDefinitions(...)` | `resourceTypes(...)` |
| `PackageStatus` enum | `InstanceStatus` enum |
| `ReleaseStrategy.DEVELOPMENT/STABLE` | same enum, but the CLI flag is lowercase: `--release-channel development\|stable` |

## Project Operations

### Create / update / clone / delete

```graphql
mutation {
  createProject(
    organizationId: "org-id"
    input: { id: "ecomm", name: "E-commerce", description: "Storefront stack" }
  ) {
    successful
    result { id name }
    messages { message }
  }
}
```

```graphql
mutation {
  cloneProject(
    organizationId: "org-id"
    sourceProjectId: "ecomm"
    input: { id: "ecomm-fork", name: "E-commerce fork" }
  ) { successful messages { message } }
}
```

`deleteProject(organizationId, id)` — all environments must be deleted first. Check `project.deletable` before calling.

## Environment Operations

### Create

```graphql
mutation {
  createEnvironment(
    organizationId: "org-id"
    projectId: "ecomm"
    input: { id: "prod", name: "Production" }
  ) { successful result { id } messages { message } }
}
```

The environment ID is the second segment of every instance slug. With project `ecomm` + env `prod`, instances are `ecomm-prod-<component-id>`.

### Fork (CLI doesn't have this — GraphQL only)

```graphql
mutation {
  forkEnvironment(
    organizationId: "org-id"
    parentId: "ecomm-prod"
    input: {
      id: "agentx7k2"
      name: "Upgrade test"
      description: "Testing upgrade of database to 1.3.0"
      copyEnvironmentDefaults: true
    }
  ) {
    successful
    result { id parent { id } }
    messages { message }
  }
}
```

Forking starts instances blank (no params copied). Per-instance secrets and remote refs are not copied — use `copyInstance` per instance after forking.

### Update / set defaults

```graphql
mutation {
  updateEnvironment(
    organizationId: "org-id"
    id: "ecomm-prod"
    input: { description: "Updated with test results" }
  ) { successful messages { message } }
}
```

```graphql
mutation {
  setEnvironmentDefault(
    organizationId: "org-id"
    environmentId: "ecomm-prod"
    resourceId: "<resource-uuid-or-slug>"
  ) { successful messages { message } }
}
```

`removeEnvironmentDefault(organizationId, id: <UUID>)` removes a default by its environment-default record id.

## Component Operations (Project Blueprint)

Components are slots in a project's blueprint, each backed by a bundle. Each environment auto-instantiates every component. CLI verbs `mass component add|remove|update|link|unlink` cover these — the GraphQL is here for completeness.

### Add a component

```graphql
mutation {
  addComponent(
    organizationId: "org-id"
    projectId: "ecomm"
    ociRepoName: "aws-aurora-postgres"
    input: { id: "db", name: "Primary Database" }
  ) { successful result { id } messages { message } }
}
```

`id` is the final slug segment of every instance for this component (e.g. `ecomm-prod-db`). Max 20 chars, lowercase alphanumeric.

### Link / unlink components

```graphql
mutation {
  linkComponents(
    organizationId: "org-id"
    input: {
      fromComponentId: "ecomm-db"
      fromField: "authentication"
      fromVersion: "~1.0"
      toComponentId: "ecomm-app"
      toField: "database"
      toVersion: "~2.0"
    }
  ) { successful result { id fromField toField } messages { message } }
}
```

`unlinkComponents(organizationId, id: <link-UUID>)` removes a link.

## Instance Operations

### Update version / release channel

```graphql
mutation {
  updateInstance(
    organizationId: "org-id"
    id: "ecomm-prod-db"
    input: { version: "~1.3", releaseStrategy: development }
  ) { successful result { id resolvedVersion } messages { message } }
}
```

`releaseStrategy` is the enum `stable | development` (note the CLI flag mirrors this lowercase form).

### Copy configuration between instances

```graphql
mutation {
  copyInstance(
    organizationId: "org-id"
    sourceId: "ecomm-prod-db"
    destinationId: "ecomm-agentx7k2-db"
    input: {
      overrides: { instance_size: "small", multi_az: false }
      copySecrets: true
      copyRemoteReferences: false
      message: "Promote prod config to upgrade test"
    }
  ) { successful result { id params } messages { message } }
}
```

Source and destination must be instances of the same component. Fields marked `$md.copyable: false` in the bundle are excluded automatically. A PLAN deployment is created on the destination so the copy can be reviewed before applying.

### Manage instance secrets

```graphql
mutation {
  setInstanceSecret(
    organizationId: "org-id"
    id: "ecomm-prod-db"
    input: { name: "DATABASE_PASSWORD", value: "..." }
  ) { successful messages { message } }
}
```

`removeInstanceSecret(organizationId, id, name)` deletes a secret.

### Reset state (escape hatch)

`orphanInstance(organizationId, id, input: { deleteState: false })` clears Terraform/OpenTofu state locks. With `deleteState: true`, it permanently removes the remote state file — the next deployment provisions from scratch.

## Deployment Operations

### Create a deployment (CLI: `mass instance deploy`)

```graphql
mutation {
  createDeployment(
    organizationId: "org-id"
    instanceId: "ecomm-prod-db"
    input: {
      action: PROVISION
      message: "Initial deployment"
      params: { instance_type: "t3.micro", storage_gb: 20 }
    }
  ) { successful result { id status action } messages { message } }
}
```

`action` is `PROVISION | PLAN | DECOMMISSION`. `params` snapshots into the deployment record — later instance edits don't mutate this row.

### Deployment approval flow (no CLI)

```graphql
mutation {
  proposeDeployment(
    organizationId: "org-id"
    instanceId: "ecomm-prod-db"
    input: {
      action: PROVISION
      message: "Bump db_version 15 → 16"
      params: { db_version: "16" }
    }
  ) { successful result { id status } messages { message } }
}
```

`approveDeployment`, `rejectDeployment`, `abortDeployment` each take `(organizationId, id)` of the proposal. Proposals enter `PROPOSED` status and don't execute until approved.

## Resource Type Operations

`mass resource-type publish <file>` is the right path for bundle development. The GraphQL `publishResourceType` mutation exists but is `@deprecated` — described in the schema as a "transitional shim from V0 `publishArtifactDefinition`" while resource types migrate to OCI-native publishing. Do not build new tooling against it.

## Resource Operations

```graphql
mutation {
  createResource(
    organizationId: "org-id"
    input: {
      name: "External RDS"
      resourceTypeId: "postgres"
      payload: { ... matches resource type schema ... }
    }
  ) { successful result { id name } messages { message } }
}
```

Use this to import infrastructure not deployed through Massdriver. Provisioned resources (those created by bundle deployments) are managed by the platform and don't need this mutation.

## Common Queries

### Project with environments and blueprint

```graphql
query {
  project(organizationId: "org-id", id: "ecomm") {
    id
    name
    environments { id name }
    components { id name bundle { name } }
    links { id fromField toField }
  }
}
```

### Environment with instances and defaults

```graphql
query {
  environment(organizationId: "org-id", id: "ecomm-prod") {
    id
    name
    description
    instances { id name status resolvedVersion params }
    defaults { id resource { id name } }
    parent { id }
  }
}
```

### Instance details (replaces v1 `package` query)

```graphql
query {
  instance(organizationId: "org-id", id: "ecomm-prod-db") {
    id
    name
    status
    params
    paramsSchema
    resolvedVersion
    deployedVersion
    releaseStrategy
    component { id bundle { name version } }
    connections { fromField toField fromInstance { id } }
  }
}
```

### Deployments and logs

```graphql
query {
  deployments(organizationId: "org-id", instanceId: "ecomm-prod-db", cursor: { limit: 10 }) {
    items { id status action version message createdAt }
    cursor { next }
  }
}
```

```graphql
query {
  deployment(organizationId: "org-id", id: "<deployment-uuid>") {
    id status action message createdAt finishedAt
  }
}
```

```graphql
query {
  deploymentLogs(organizationId: "org-id", id: "<deployment-uuid>") {
    id
    logs { content metadata { step timestamp } }
  }
}
```

### Bundles / OCI repos

```graphql
query {
  ociRepos(organizationId: "org-id", cursor: { limit: 20 }) {
    items { id name attributes }
    cursor { next }
  }
}
```

```graphql
query {
  bundles(organizationId: "org-id", cursor: { limit: 20 }) {
    items {
      name
      releases(strategy: development, cursor: { limit: 5 }) {
        items { version description }
      }
    }
  }
}
```

### Resource types

```graphql
query {
  resourceTypes(organizationId: "org-id") {
    items { id name label schema ui { connectionOrientation environmentDefaultGroup } }
  }
}
```

## Enums

### `DeploymentAction`
- `PROVISION` — apply changes
- `PLAN` — dry run, no state changes
- `DECOMMISSION` — tear down

### `DeploymentStatus`
- `PROPOSED` — proposal pending review (only via `proposeDeployment`)
- `PENDING` — queued
- `RUNNING` — in flight
- `COMPLETED` — success
- `FAILED` — failed
- `ABORTED` — cancelled
- `REJECTED` — proposal rejected

### `InstanceStatus`
- `INITIALIZED` — slot exists, never deployed
- `PROVISIONED` — successfully deployed
- `DECOMMISSIONED` — torn down
- `FAILED` — last deployment failed
- `EXTERNAL` — imported / not managed by Massdriver

### `ReleaseStrategy`
- `stable` — only stable releases (default)
- `development` — accepts dev releases too

## ID conventions

- **Project ID**: lowercase alphanumeric, max 20 chars, immutable.
- **Environment ID** (full): `<project>-<env-suffix>` (e.g. `ecomm-prod`). The `id` field on `CreateEnvironmentInput` is just the suffix — the project segment is derived from `projectId`.
- **Component ID** (project-scoped): `<project>-<component-suffix>` (e.g. `ecomm-db`). `AddComponentInput.id` is just the suffix.
- **Instance ID**: `<project>-<env>-<component>` (e.g. `ecomm-prod-db`).
- **Resource ID**: either a UUID (imported resources) or `<project>-<env>-<component>-<artifact-field>` slug (provisioned).

## Tips

1. Prefer the CLI for `mass bundle publish`, `mass instance deploy --follow`, and `mass deployment logs` — they are the most reliable paths.
2. Use GraphQL when you need many related entities in one round-trip (e.g. a project plus its components, links, environments, and instances).
3. Always check `messages { message }` on mutation results for detailed error info.
4. Mutations that take an `input` typically also publish a JSON Schema at `/graphql/v2/inputs/<name>.json` — useful for client-side validation or form generation.
5. Most queries that return lists accept `cursor: { limit: N }` and return `cursor { next }` for pagination.
