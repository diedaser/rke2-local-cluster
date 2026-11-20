# Operations

Day-2 procedures for the `rke2-cluster` and `rancher` building blocks. Run them in a maintenance window, and take an etcd snapshot first.

Resource addresses (used with `tofu apply -replace`):

- First server: `module.server_init.aws_instance.pinned[0]`
- Joining servers: `module.server_join.aws_instance.pinned[i]` (`i = 0` is the second server)
- Agents: `module.agents.aws_instance.rolling[i]`

Node access without SSH: AWS Systems Manager Session Manager is not set up (no instance profile). Use break-glass SSH (`ssh_key_name`, `ssh_allowed_cidrs`) from a bastion in the VPC, or the EC2 serial console.

## RKE2 upgrades

Check the [Rancher support matrix](https://www.suse.com/suse-rancher/support-matrix/) for the running Rancher version first, and cite the row in the PR ([ADR-009](adr/ADR-009-version-pinning.md)). Upgrade one minor version at a time.

### Agents

Bump `rke2_version` and run the building block. Agents use the "rolling" node pool variant: the changed cloud-init replaces each agent create-before-destroy. Review the plan; it should replace only `module.agents...rolling[*]`.

### Servers

Server instances ignore user data and AMI changes ([ADR-006](adr/ADR-006-fixed-registration-address.md)). Bumping `rke2_version` therefore changes only the cloud-init of servers created in the future. It never replaces an etcd member. Upgrade the existing servers in place, one at a time:

1. Bump `rke2_version` in the definition and run the building block. Confirm the plan replaces no server.
2. For each server, one after another:
   ```bash
   kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
   # on the node (serial console or break-glass SSH):
   curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=<new version> INSTALL_RKE2_TYPE=server sh -
   systemctl restart rke2-server
   kubectl uncordon <node>
   ```
   Wait until the node is `Ready` and etcd is healthy before moving to the next server.

Alternative: install the [system-upgrade-controller](https://docs.rke2.io/upgrades/automated_upgrade) and apply a server `Plan` with `concurrency: 1` and `cordon: true`, using the same version.

## Replacing a server

### A joining server

1. Remove the etcd member and the node:
   ```bash
   kubectl delete node <node>
   ```
   RKE2 removes the etcd member when its node is deleted. Check with `etcdctl member list` from another server.
2. Replace the instance:
   ```bash
   tofu apply -replace='module.server_join.aws_instance.pinned[<i>]'
   ```
   The new server joins through the internal NLB with the current cloud-init and AMI.

In meshStack this requires a platform-team run with the replace option, or a local run against the instance's state (never in parallel with meshStack, see [ADR-005](adr/ADR-005-meshstack-state-backend.md)).

### The first server (`server_init`, index 0)

**Do not replace it casually.** Its cloud-init carries the CA files and has no `server:` key. A fresh instance with an empty disk would initialise a **new, empty cluster** instead of joining the existing one. Its `user_data` only matters on first boot: an existing server keeps working from its persisted `/var/lib/rancher/rke2`.

If server 0 is lost but the other servers still have etcd quorum:

1. Delete its node (`kubectl delete node <server-0>`) so its etcd member is removed.
2. Do **not** recreate it with OpenTofu. Run the cluster on the remaining servers until the next maintenance window. The NLB health checks take the dead target out of rotation automatically.
3. To get back to full size, restore into a fresh first server ([disaster recovery](#disaster-recovery)), then re-join the others.

If quorum is lost, follow [disaster recovery](#disaster-recovery).

## etcd snapshots

Servers take snapshots as configured by `etcd_snapshot_schedule_cron` (default `0 */6 * * *`) and keep `etcd_snapshot_retention` (default 10) per server. Each snapshot is written to `/var/lib/rancher/rke2/server/db/snapshots/` and uploaded to `s3://<backup_bucket_name>/etcd/` with the server instance profile ([ADR-014](adr/ADR-014-backups-to-s3.md)). With 3 servers the bucket holds up to 30 snapshots.

- On-demand snapshot: `rke2 etcd-snapshot save --name pre-change` (uploads to S3 too)
- List snapshots, local and S3: `rke2 etcd-snapshot list`
- From the workstation: `aws s3 ls s3://<backup_bucket_name>/etcd/`

### Servers created before ADR-014

Servers ignore user data changes, so servers that existed before the S3 change get the instance profile in place but no `etcd-s3*` settings. On each such server (serial console or break-glass SSH), append to `/etc/rancher/rke2/config.yaml`, then restart one server at a time:

```yaml
etcd-s3: true
etcd-s3-bucket: "<backup_bucket_name>"
etcd-s3-region: "<region>"
etcd-s3-endpoint: "s3.<region>.amazonaws.com"
etcd-s3-folder: "etcd"
etcd-snapshot-retention: 10
```

Rebuilding the cluster (new servers get the settings from cloud-init) is the alternative.

## Disaster recovery

Restore an etcd snapshot on the first server with `cluster-reset`:

1. Stop RKE2 on **all** servers: `systemctl stop rke2-server`.
2. On server 0, restore either a local snapshot or one from S3, then start RKE2:
   ```bash
   # local file
   rke2 server --cluster-reset --cluster-reset-restore-path=/var/lib/rancher/rke2/server/db/snapshots/<snapshot>
   # from S3: the etcd-s3* settings come from config.yaml; pass the snapshot NAME, not a path
   rke2 server --cluster-reset --etcd-s3 --cluster-reset-restore-path=<snapshot-name>
   systemctl start rke2-server
   ```
   `aws s3 ls s3://<backup_bucket_name>/etcd/` lists the names.
3. On every other server: `rm -rf /var/lib/rancher/rke2/server/db`, then `systemctl start rke2-server`. They re-join through the internal NLB.

If server 0 itself is gone, create a replacement with the same CA files (`tofu apply -replace='module.server_init.aws_instance.pinned[0]'`), stop RKE2 there before it serves workloads, and restore as above. The CA set is in state, so restored certificates and the kubeconfig stay valid.

## Rancher backups

The `rancher` building block installs the rancher-backup operator and a recurring `Backup` named `rancher-scheduled` ([ADR-014](adr/ADR-014-backups-to-s3.md)): resource set `rancher-resource-set-full`, schedule `rancher_backup_schedule` (default `0 3 * * *`, UTC), newest `rancher_backup_retention` (default 10) kept in `s3://<backup_bucket_name>/rancher/`, encrypted.

- Status: `kubectl get backups.resources.cattle.io rancher-scheduled -o wide`
- Archives: `aws s3 ls s3://<backup_bucket_name>/rancher/`
- One-off backup before a change: apply a `Backup` without `schedule` and the same `resourceSetName` and `encryptionConfigSecretName`.

### Restore into the same cluster

```yaml
apiVersion: resources.cattle.io/v1
kind: Restore
metadata:
  name: restore-<date>
spec:
  backupFilename: <archive>.tar.gz.enc
  encryptionConfigSecretName: rancher-backup-encryption
```

The operator reads from its default S3 location. Rancher restarts during the restore.

### Restore into a new cluster (migration, DR)

1. Get the encryption config: `aws secretsmanager get-secret-value --secret-id <prefix>-rancher-backup-encryption --query SecretString --output text > encryption-provider-config.yaml`. Without it the archives cannot be read.
2. On the new cluster, install `rancher-backup-crd` and `rancher-backup` (same chart version) with S3 credentials for `rancher/`, and create the secret `rancher-backup-encryption` in `cattle-resources-system` from the file (key `encryption-provider-config.yaml`).
3. Apply a `Restore` with `prune: false`, then install Rancher with the same version and hostname. Follow "Migrating Rancher to a New Cluster" in the Rancher docs for the version you run.

Shortcut for a meshStack rebuild: order `rke2-cluster` + `rancher` again, then run step 3 against the new cluster. The new `rancher` instance creates its own encryption key, so first replace the `rancher-backup-encryption` secret with the old config from step 1.

### rancher-backup access key rotation

`tofu apply -replace=aws_iam_access_key.rancher_backup` in the `rancher` building block (or the equivalent meshStack run). The Kubernetes secret is updated in the same run; the operator picks it up for the next backup.

## Downstream user password rotation

The `rancher` building block creates the Rancher user `meshstack-downstream` (global roles `user-base`, `clusters-create`) for the downstream-cluster building block and stores its login in `<prefix>-rancher-downstream` ([ADR-015](adr/ADR-015-downstream-clusters.md)). Never replace or delete the user while downstream clusters exist: they are owned by its user ID.

1. `tofu apply -replace=random_password.downstream` in the `rancher` building block (or the equivalent meshStack run). The secret gets the new password; the Rancher user keeps the old one, because its password is ignored after creation.
2. As admin, set the same password on the user in Rancher (**Users & Authentication → Users → meshstack-downstream → Edit**), reading it from the secret: `aws secretsmanager get-secret-value --secret-id <prefix>-rancher-downstream --query SecretString --output text | jq -r .password`.

Between step 1 and step 2, downstream-cluster runs fail to log in. Do both in one window.

## Admin certificate renewal

The admin client certificate is valid for `admin_cert_validity_hours` (default one year). Any run within the last 30 days (`early_renewal_hours = min(720, validity / 4)`) issues a new certificate. The kubeconfig changes and is written as a new version of the same Secrets Manager secret; name and ARN stay the same.

You do not need to re-run `rancher` for this. It looks up the kubeconfig by `kubeconfig_secret_name` on every run. Schedule an `rke2-cluster` run (or drift detection plus approval) at least once a month so the certificate never expires.

## CA rotation

This is ADR-003-sensitive: changes to `pki.tf` require an update to [ADR-003](adr/ADR-003-opentofu-generated-pki.md) and a PR note.

1. Generate the new CA set offline, matching the files listed in `pki.tf`.
2. Rotate in the cluster with `rke2 certificate rotate-ca --path=<dir with new CA files>` on a server, then restart RKE2 on all nodes as described in the RKE2 docs.
3. Make state match: replace the CA resources so OpenTofu stops issuing kubeconfigs from the old CA, for example `tofu apply -replace='tls_private_key.ca["server-ca"]' ...`. Because generated keys cannot be imported, you either rotate to the keys OpenTofu generates (extract them from state first and use them in step 2), or adapt `pki.tf` to accept supplied CAs.
4. The join token hash (`K10<sha256(server-ca)>`) changes with `server-ca`. New nodes get the new token only through new cloud-init, so replace agents afterwards.

## Rancher upgrades

1. Check the support matrix for the target Rancher version against the running RKE2 version.
2. Bump `rancher_version` (chart version, no `v`). For a new Rancher **minor**, also bump the `rancher/rancher2` provider major in `modules/rancher/buildingblock/versions.tf`, because v15 corresponds to Rancher 2.15 ([ADR-008](adr/ADR-008-rancher-installation.md)), and `rancher_backup_chart_version` to the line whose `catalog.cattle.io/rancher-version` annotation covers the new minor (110.x = 2.15).
3. Upgrade cert-manager separately if needed, one component per PR.
4. Run with "Version upgrade" approval and review the Helm diff.

## NAT gateway

There is one NAT gateway, in the first AZ. If that AZ fails, nodes lose internet egress (image pulls, Helm repos), but in-cluster traffic, the NLBs and running workloads keep working. For zone-redundant egress, add a NAT gateway per AZ (not implemented).

## Runner access key rotation

The backplane IAM user's access key is long-lived. Rotate it at least every 90 days:

1. `tofu apply -replace=aws_iam_access_key.meshstack_runner` in `modules/rke2-cluster/backplane`.
2. Create a new draft of **both** definitions with the new `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, and release them.
3. Upgrade existing building block instances to the new definition versions.

Between step 1 and step 3 the old key no longer exists, so runs fail. Do it in a window without scheduled runs (drift detection included).

### Node-driver access key ([ADR-015](adr/ADR-015-downstream-clusters.md))

Rancher uses this key to create and delete downstream EC2 instances. Rotate it on the same schedule:

1. `tofu apply -replace=aws_iam_access_key.node_driver` in `modules/rke2-cluster/backplane`.
2. Create a new draft of the `downstream-cluster` definition with the new `node_driver_access_key_id` and `node_driver_secret_access_key`, release it, and upgrade the instances. Each run updates its `rancher2_cloud_credential`.

Until an instance is upgraded, Rancher cannot scale, upgrade or delete that downstream cluster's nodes. Running workloads are unaffected.

## State encryption passphrase

Never change `TF_VAR_state_encryption_passphrase` on a definition. Existing state then becomes unreadable ([ADR-004](adr/ADR-004-state-encryption.md)). To rotate it:

1. Add a `fallback` block to `encryption.tf` with the old key provider.
2. Run every instance once, which re-encrypts the state with the new passphrase.
3. Remove the fallback.

## Deleting

1. Delete every `downstream-cluster` building block first (meshStack does not enforce the order), then the `rancher` building block. This uninstalls the Helm releases, deletes the rancher-backup IAM user and the admin secret (immediately), and schedules the backup encryption secret for deletion in 30 days. Restore it with `aws secretsmanager restore-secret` if the backups are still needed. Rancher's uninstall leaves CRDs and some namespaces behind; this is irrelevant if the cluster is deleted next.
2. Delete the `rke2-cluster` building block. This destroys servers, agents, root volumes, both NLBs, the NAT gateway and its EIP, the VPC with subnets, route tables and security groups, the placement group, the server IAM role and instance profile, and the kubeconfig secret in Secrets Manager.
   - The backup bucket is deleted only with `backup_force_destroy = true`. With the default `false`, the run fails on the non-empty bucket on purpose: keep a copy of what you need, then `aws s3 rm s3://<backup_bucket_name> --recursive` and run the delete again.
3. Check that nothing tagged `meshstack-building-block=<uuid>` remains in the account and region (Resource Groups → Tag Editor).
