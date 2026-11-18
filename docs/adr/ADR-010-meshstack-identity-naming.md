# ADR-010: meshStack is the source of identity and naming

- **Status:** Accepted, 2026-10-16

## Decision

`modules/_shared/naming` derives names and labels from meshStack-injected identifiers:

- Prefix: `<name>-<first 8 hex chars of building_block_uuid>`, for example `mgmt-3f2b8c1e`. This makes names unique per instance within an account and region, which matters for Secrets Manager lookups by name. Names with hard AWS length limits (NLB and target group names, 32 characters) use `rke2-<short id>-<suffix>` instead; their `Name` tag carries the full prefix.
- Labels: `meshstack-workspace`, `meshstack-project`, `meshstack-building-block`, `managed-by=opentofu`, `building-block=<name>`. They are applied as AWS tags on every resource (provider `default_tags`, plus explicit tags on EC2 root volumes), Kubernetes node labels and namespace labels.

Users only choose `cluster_name`, which is validated. They never type free-form resource names.
