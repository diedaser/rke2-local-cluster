# Architecture Decision Records

| ADR | Title | Status |
|---|---|---|
| [ADR-001](ADR-001-two-building-blocks.md) | Two building blocks instead of one | Accepted |
| [ADR-002](ADR-002-no-ssh-no-local-exec.md) | No SSH, no local-exec, no host tools | Accepted |
| [ADR-003](ADR-003-opentofu-generated-pki.md) | OpenTofu-generated cluster PKI | Accepted |
| [ADR-004](ADR-004-state-encryption.md) | OpenTofu native state encryption is mandatory | Accepted |
| [ADR-005](ADR-005-meshstack-state-backend.md) | meshStack built-in state backend | Accepted |
| [ADR-006](ADR-006-fixed-registration-address.md) | Fixed registration address through a load balancer | Accepted |
| [ADR-007](ADR-007-readiness-polling.md) | Readiness is polled, not slept | Accepted |
| [ADR-008](ADR-008-rancher-installation.md) | Rancher installation choices | Accepted |
| [ADR-009](ADR-009-version-pinning.md) | Strict version pinning, support-matrix driven | Accepted |
| [ADR-010](ADR-010-meshstack-identity-naming.md) | meshStack is the source of identity and naming | Accepted |
| [ADR-011](ADR-011-cis-hardening.md) | CIS hardening profile by default | Accepted |
| [ADR-012](ADR-012-secrets-in-secrets-manager.md) | Secrets go to a secret store, outputs carry references only | Accepted |
| [ADR-013](ADR-013-tenant-project-scope.md) | Credentials are scoped to the tenant's AWS account | Accepted |
| [ADR-014](ADR-014-backups-to-s3.md) | etcd snapshots and Rancher backups go to S3 | Accepted |
| [ADR-015](ADR-015-downstream-clusters.md) | Downstream clusters provisioned by Rancher on EC2 | Accepted |

New ADRs: copy the structure (Status, Context, Decision, Consequences), use the next number, and add a row here.
