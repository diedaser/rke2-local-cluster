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

Servers take local snapshots as configured by `etcd_snapshot_schedule_cron` (default `0 */6 * * *`) and `etcd_snapshot_retention` (default 28). Snapshots are stored in `/var/lib/rancher/rke2/server/db/snapshots/` on each server.

- On-demand snapshot: `rke2 etcd-snapshot save --name pre-change`
- List snapshots: `rke2 etcd-snapshot list`

S3 targets are not wired into the module yet. Until then, configure them by hand (`etcd-s3*` keys in `/etc/rancher/rke2/config.yaml` on each server), or copy snapshots off-host. Local snapshots die with the root volumes (`delete_on_termination = true`). An S3 target needs an instance profile with `s3:PutObject`, which the module does not create yet.

## Disaster recovery

Restore an etcd snapshot on the first server with `cluster-reset`:

1. Stop RKE2 on **all** servers: `systemctl stop rke2-server`.
2. On server 0, copy the snapshot to the node if needed, then run:
   ```bash
   rke2 server --cluster-reset --cluster-reset-restore-path=/var/lib/rancher/rke2/server/db/snapshots/<snapshot>
   systemctl start rke2-server
   ```
3. On every other server: `rm -rf /var/lib/rancher/rke2/server/db`, then `systemctl start rke2-server`. They re-join through the internal NLB.

If server 0 itself is gone, create a replacement with the same CA files (`tofu apply -replace='module.server_init.aws_instance.pinned[0]'`), stop RKE2 there before it serves workloads, and restore as above. The CA set is in state, so restored certificates and the kubeconfig stay valid.

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
2. Bump `rancher_version` (chart version, no `v`). For a new Rancher **minor**, also bump the `rancher/rancher2` provider major in `modules/rancher/buildingblock/versions.tf`, because v15 corresponds to Rancher 2.15 ([ADR-008](adr/ADR-008-rancher-installation.md)).
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

## State encryption passphrase

Never change `TF_VAR_state_encryption_passphrase` on a definition. Existing state then becomes unreadable ([ADR-004](adr/ADR-004-state-encryption.md)). To rotate it:

1. Add a `fallback` block to `encryption.tf` with the old key provider.
2. Run every instance once, which re-encrypts the state with the new passphrase.
3. Remove the fallback.

## Deleting

1. Delete the `rancher` building block first. This uninstalls the Helm releases and deletes the admin secret in Secrets Manager (immediately, no recovery window). Rancher's uninstall leaves CRDs and some namespaces behind; this is irrelevant if the cluster is deleted next.
2. Delete the `rke2-cluster` building block. This destroys servers, agents, root volumes, both NLBs, the NAT gateway and its EIP, the VPC with subnets, route tables and security groups, the placement group and the kubeconfig secret in Secrets Manager.
3. Check that nothing tagged `meshstack-building-block=<uuid>` remains in the account and region (Resource Groups → Tag Editor).
