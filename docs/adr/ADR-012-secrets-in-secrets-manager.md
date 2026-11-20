# ADR-012: Secrets go to a secret store, outputs carry references only

- **Status:** Accepted, 2026-10-16. Revised 2026-11-18 for AWS (was: OpenStack Barbican).

## Context

meshStack does not support sensitive outputs. Every mapped output is visible in meshPanel.

## Decision

- `rke2-cluster` writes the admin kubeconfig to AWS Secrets Manager (`aws_secretsmanager_secret.kubeconfig` + `_version`, named `<prefix>-kubeconfig`). It outputs `kubeconfig_secret_name` and `kubeconfig_secret_arn`. The version is written only after `/readyz` succeeded.
- `rancher` takes **`kubeconfig_secret_name`** (Parent Building Block Output) and reads it with `data.aws_secretsmanager_secret_version`. It validates that the name ends in `-kubeconfig` and that the payload is a kubeconfig. The name is stable; the ARN carries a random suffix, so the name is the simpler contract.
- `rancher` stores the admin URL, username, password and API token as JSON in `<prefix>-rancher-admin`, and outputs `admin_secret_name` and `admin_secret_arn`.
- Secrets Manager secrets are mutable. A renewed admin certificate writes a new secret version in place; no replacement, no window without a secret.
- `recovery_window_in_days = 0`: destroying a building block deletes its secret immediately. The credentials are worthless without the cluster, and a recovery window would block re-creating the same name.
- Optional `kms_key_arn` encrypts the secrets (and EBS volumes) with a customer managed key; default is `aws/secretsmanager`.
- Building blocks have **no** Terraform `sensitive` outputs at all. `scripts/validate-all.sh` enforces this. The Rancher backup encryption config is escrowed the same way (`<prefix>-rancher-backup-encryption`, [ADR-014](ADR-014-backups-to-s3.md)). Break-glass access uses `scripts/fetch-kubeconfig.sh` (and `scripts/fetch-rancher-admin.sh` for the Rancher admin credentials), which reads Secrets Manager with the `aws` CLI instead of a state output.

## Consequences

- The runner IAM policy needs `secretsmanager:*Secret*` on the account/region (backplane), and `kms:Decrypt`/`GenerateDataKey` when a customer managed key is used.
- Names must be unique per account and region. The UUID-based prefix ([ADR-010](ADR-010-meshstack-identity-naming.md)) guarantees this.
- Anyone with `secretsmanager:GetSecretValue` on the account is cluster-admin and Rancher admin. Restrict human access to the platform team.
- Changes to `secrets.tf` require an update to this ADR (CONTRIBUTING.md rule 6).
