# GraphQL API Reference

Massdriver exposes a GraphQL API at `https://api.massdriver.cloud/graphql/v2`. The full schema is at `https://api.massdriver.cloud/graphql/v2/schema.graphql`.

**Every operation is available as an MCP tool — use those.** GraphQL's remaining value is reads: one query spanning several related entities (a project plus its components, links, environments, and instances) beats a chain of tool calls. This document covers those queries plus shared conventions.

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

### Instance details

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
      releases(cursor: { limit: 5 }) {
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
- `PROPOSED` — proposal pending review (via `propose_deployment` / `rollback_deployment`)
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

### Release channels
Not an enum — the channel rides the version constraint. A `+dev` suffix (`latest+dev`, `~1+dev`) accepts development releases; without it, only stable releases resolve.

## ID conventions

- **Project ID**: lowercase alphanumeric, max 20 chars, immutable.
- **Environment ID** (full): `<project>-<env-suffix>` (e.g. `ecomm-prod`). Creation inputs take just the suffix — the project segment is derived from the project.
- **Component ID** (project-scoped): `<project>-<component-suffix>` (e.g. `ecomm-db`). Creation inputs take just the suffix.
- **Instance ID**: `<project>-<env>-<component>` (e.g. `ecomm-prod-db`).
- **Resource ID**: either a UUID (imported resources) or `<project>-<env>-<component>-<artifact-field>` slug (provisioned).

## Tips

1. Most queries that return lists accept `cursor: { limit: N }` and return `cursor { next }` for pagination.
2. The `deploymentLogs` query returns a snapshot; the MCP `get_deployment_logs` tool with `follow: true` is the better way to watch a running deployment.
