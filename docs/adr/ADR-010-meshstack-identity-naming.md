# ADR-010: meshStack is the source of identity and naming

- **Status:** Accepted, 2026-10-16

## Decision

`modules/_shared/naming` derives names and labels from meshStack-injected identifiers:

- Prefix: `<name>-<first 8 hex chars of building_block_uuid>`, for example `mgmt-3f2b8c1e`. This makes names unique per instance within a project, which matters for Barbican lookups by name.
- Labels: `meshstack-workspace`, `meshstack-project`, `meshstack-building-block`, `managed-by=opentofu`, `building-block=<name>`. They are applied as OpenStack tags (`key=value` strings), Nova metadata, Barbican metadata, Kubernetes node labels and namespace labels.

Users only choose `cluster_name`, which is validated. They never type free-form resource names.
