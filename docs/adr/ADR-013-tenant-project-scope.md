# ADR-013: Credentials are scoped to the tenant's OpenStack project

- **Status:** Accepted, 2026-10-16

## Context

The runner authenticates with an OpenStack application credential (static inputs). Application credentials are bound to one project and cannot be re-scoped to another. meshStack, however, passes the tenant's project through the Platform Tenant ID (`openstack_project_id`), which may differ per meshProject.

## Decision

Both building blocks read `data.openstack_identity_auth_scope_v3.current` and fail when its `project_id` differs from `openstack_project_id`:

- `rke2-cluster`: precondition on `openstack_networking_network_v2.this`
- `rancher`: precondition on `data.http.api_readyz`

Nothing is created in the wrong project.

## Consequences

- One definition with one credential serves exactly one OpenStack project.
- Options for multiple projects (future work):
  - one definition (or definition version with different static inputs) per project, each with its own application credential from the backplane
  - a service user with password authentication and `tenant_id = var.openstack_project_id`, with its role assignment in each tenant project managed by the meshStack OpenStack replicator
