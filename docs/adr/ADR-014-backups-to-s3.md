# ADR-014: etcd snapshots and Rancher backups go to S3

- **Status:** Accepted, 2026-11-19.

## Context

Local etcd snapshots live on the server root volumes, which are deleted with the instances (`delete_on_termination = true`). Losing the servers therefore lost every snapshot, and Rancher had no backup at all. Both need an off-cluster copy that survives the cluster.

Constraints:

- No SSH and no host tools (ADR-002): RKE2 must upload snapshots by itself, and the rancher-backup operator must be configured through providers.
- Node user data is applied once; server instances ignore later changes (ADR-006).
- IMDS hop limit 1 keeps pods away from the node's credentials. That is deliberate and stays.
- The runner's IAM user must not be able to escalate its own privileges through the IAM principals it creates.

## Decision

- **One bucket per cluster**, created by `rke2-cluster`: `rke2-backup-<short_id>-<account_id>`, private (public access block, `BucketOwnerEnforced`, TLS-only bucket policy), SSE-S3 or SSE-KMS with `kms_key_arn`, no versioning. Prefixes: `etcd/` (RKE2) and `rancher/` (rancher-backup). The name is output as `backup_bucket_name` and mapped into `rancher` as a Parent Building Block Output.
- **etcd:** every server config sets `etcd-s3: true` with bucket, region, endpoint and folder `etcd`, and no access key. RKE2 runs on the host and takes credentials from the server instance profile (`/rke2/` role, limited to `etcd/*`). Agents get no profile. `etcd_snapshot_retention` (default 10) applies per server, locally and in S3.
- **Rancher:** `rancher` installs `rancher-backup-crd` and `rancher-backup` (charts.rancher.io, version pinned to the Rancher minor) with the bucket as the default S3 location, and a recurring `Backup` (`rancher-resource-set-full`, `rancher_backup_schedule`, `retentionCount = rancher_backup_retention`, default 10) through a local Helm chart, because `kubernetes_manifest` would need the CRD at plan time (ADR-001).
  - The operator is a pod, so it uses a dedicated IAM user (`/rke2-backup/`, limited to `rancher/*`) whose key is stored in a Kubernetes secret, rather than weakening IMDS for every pod.
  - The full resource set includes secrets, so backups are encrypted with a generated AES-CBC `EncryptionConfiguration`. It is escrowed in Secrets Manager (`<prefix>-rancher-backup-encryption`, 30-day recovery window); only the secret name is output (ADR-012).
- **Privilege-escalation guard:** the backplane creates the policy `/rke2/rke2-backup-boundary` (S3 on `rke2-backup-*`, plus the KMS key). The runner may call `iam:CreateRole`, `iam:PutRolePolicy`, `iam:CreateUser` and `iam:PutUserPolicy` only with that permissions boundary attached, and `iam:PassRole` only for `/rke2/` roles to EC2. Whatever inline policy the runner writes, the created principals can never exceed the backup buckets.
- **Deletion:** `backup_force_destroy` (default `false`) keeps the bucket and its backups when `rke2-cluster` is deleted; the destroy then fails until the bucket is emptied. The standalone example sets it to `true`.

## Consequences

- The backplane must be re-applied before the first run with this change (new IAM permissions and the boundary policy).
- Existing servers do not pick up `etcd-s3` from changed user data. They get the instance profile in place, but S3 uploads start only on servers created afterwards, or after the `etcd-s3*` keys are added to `/etc/rancher/rke2/config.yaml` by hand (`docs/operations.md`).
- With 3 servers and retention 10, the bucket holds up to 30 etcd snapshots (10 per server).
- The rancher-backup IAM access key is long-lived; rotation is a documented manual step.
- The escrowed encryption config is the only way to read the Rancher backups. Losing it makes them worthless.
- The rancher-backup chart version follows the Rancher minor (110.x = Rancher 2.15) and is bumped together with `rancher_version` (ADR-009).
