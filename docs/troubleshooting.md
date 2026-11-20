# Troubleshooting

| Symptom | Section |
|---|---|
| `rke2-cluster` run times out on `/readyz` | [API readiness timeout](#api-readiness-timeout) |
| "The AWS credentials belong to account ..." | [Account mismatch](#credentials-for-the-wrong-account) |
| `AccessDenied` / `UnauthorizedOperation` | [IAM permissions](#iam-permissions) |
| `InvalidParameterValue`/`Unsupported` on instance creation | [Instance type or AMI](#instance-type-or-ami-rejected) |
| User data exceeds the EC2 limit | [User data too large](#user-data-too-large) |
| Joining servers or agents never appear | [Token CA hash](#joining-nodes-token-ca-hash-does-not-match) |
| `rancher` run fails on `/ping` | [Rancher ping fails](#rancher-ping-fails) |
| No etcd snapshots or Rancher backups in S3 | [Backups missing in S3](#backups-missing-in-s3) |
| `rke2-cluster` delete fails with `BucketNotEmpty` | [Backups missing in S3](#backups-missing-in-s3) |
| `rancher` destroy hangs or fails on `/ping` | [Destroy blocked by the ping check](#destroy-blocked-by-the-ping-check) |
| Let's Encrypt certificate not issued | [Let's Encrypt](#lets-encrypt) |
| "secret with this name is already scheduled for deletion" | [Secret scheduled for deletion](#secret-scheduled-for-deletion) |
| Pods rejected by PodSecurity | [PSA violations](#psa-violations-under-the-cis-profile) |
| Plan fails although nothing changed | [Cluster down at plan time](#plan-fails-because-the-cluster-is-down) |
| State cannot be decrypted | [State decryption](#state-cannot-be-decrypted) |

## API readiness timeout

`data.http.api_readyz` retries 120 x 10 s. If the API never answers:

1. **The runner cannot reach 6443.** Add the runner's egress IPs to `runner_egress_cidrs` (they land in the NLB security group). Keep `public_load_balancer = true` unless the runner sits inside the VPC (self-hosted runner, VPN, peering). Test from a host with the same egress: `curl -k https://<lb_dns_name>:6443/readyz` should return 401 or `ok`, not a timeout.
   - In `examples/standalone/`, the runner is your workstation: `api_allowed_cidrs` must contain its egress IP (`curl https://checkip.amazonaws.com`). The `198.51.100.10/32` placeholder from `terraform.tfvars.example` is a documentation address and blocks you. A blocked port looks like a slow boot: the run sits on `Still reading...` for the full 20 minutes.
2. **cloud-init or the RKE2 install failed.** Read the console output (`aws ec2 get-console-output --latest --instance-id <id> --output text`), or check `/var/log/cloud-init-output.log`, `journalctl -u rke2-server` and `cloud-init status --long` on the node (serial console or break-glass SSH). Typical causes:
   - Nodes cannot reach `get.rke2.io` or GitHub: NAT gateway missing or not `available`, private route table without `0.0.0.0/0 → nat`. Or set `rke2_install_script_url` to a reachable mirror.
   - A custom AMI without cloud-init, `curl` or gzip user data support.
   - Under the CIS profile, the `etcd` user or the sysctls are missing because of a non-standard image.
3. **NLB targets unhealthy.** `aws elbv2 describe-target-health --target-group-arn <arn>`. Targets only turn healthy once RKE2 listens, and registration alone takes a few minutes. `Target.FailedHealthChecks` with a healthy RKE2 means the node security group does not allow the NLB security group on that port.

## Credentials for the wrong account

The precondition compares `aws sts get-caller-identity` with `aws_account_id` (Platform Tenant ID). The access key belongs to a different account than the tenant. Use a definition whose key matches the tenant's account ([ADR-013](adr/ADR-013-tenant-project-scope.md)).

## IAM permissions

The runner's permissions are in `modules/rke2-cluster/backplane/main.tf`: two customer managed policies attached to the IAM user, `<iam_user_name>-infrastructure` (EC2/VPC/NLB, restricted to one region through `aws:RequestedRegion`) and `<iam_user_name>-identity` (backup bucket, bounded IAM principals, Secrets Manager, KMS). They are managed policies because inline user policies are capped at 2048 bytes in total.

- `AWS_REGION` on the definition differs from the backplane `region`: every call is denied. Align them.
- First NLB in an account: the policy allows `iam:CreateServiceLinkedRole` for Elastic Load Balancing. If an SCP denies it, create the role once as admin: `aws iam create-service-linked-role --aws-service-name elasticloadbalancing.amazonaws.com`.
- Customer managed KMS key: the backplane must be applied with the same `kms_key_arn`, and the key policy must allow the IAM user (or delegate to IAM).
- An SCP or permission boundary can still deny actions; the error names the action.

## Instance type or AMI rejected

- The instance type's architecture must match the AMI (`m7i` = amd64, `m7g` = arm64).
- AMI IDs are regional. An AMI from another region fails with `InvalidAMIID.NotFound`.
- Not every type exists in every AZ. Set `availability_zones` to zones that offer the type: `aws ec2 describe-instance-type-offerings --location-type availability-zone --filters Name=instance-type,Values=<type>`.
- vCPU service quotas (`Running On-Demand Standard instances`) are per region; 3 x 4 vCPU plus headroom for a rolling replacement fits the default of new accounts only barely.

## User data too large

The first server's cloud-init (CA set, PSA config, RKE2 config) is gzipped and must stay below 16 KiB. A `data.cloudinit_config.node` postcondition fails the plan before anything is created. Trim additions to cloud-init, or move large files to a different delivery path.

## Joining nodes: token CA hash does not match

Joining servers and agents use `K10<sha256(server-ca cert_pem)>::server:<secret>`. `journalctl -u rke2-server` (or `rke2-agent`) shows `token CA hash does not match`. Causes:

- `/var/lib/rancher/rke2/server/tls/server-ca.crt` on the first server was changed or regenerated, for example because RKE2 started before cloud-init wrote the CA files, so RKE2 generated its own.
- `tls_self_signed_cert.ca["server-ca"]` was replaced in state, so new nodes carry a different hash.

Compare `sha256sum server-ca.crt` on server 0 with the hash in the token. Fix the underlying cause; see CA rotation in [operations](operations.md#ca-rotation).

## Rancher ping fails

`data.http.rancher_ping` expects `pong` from `https://<rancher_hostname>/ping`.

- **DNS:** the hostname must resolve, from the runner, to the cluster's `lb_dns_name` output (CNAME or Route 53 alias). Create the record before running `rancher`.
- **443 not allowed:** the runner egress IPs must be in the NLB security group's 80/443 rules (`ingress_allowed_cidrs`, plus `runner_egress_cidrs`, which is appended automatically).
- **Rancher pods not ready:** `kubectl -n cattle-system get pods` and `kubectl -n cattle-system logs deploy/rancher`.
- **Standalone without a DNS record:** leave `rancher_hostname` unset; the example then uses the NLB DNS name. With a custom hostname, map it to one of the NLB's IPs on your workstation (`getent ahostsv4 <lb_dns_name>`, then add `<ip> <rancher_hostname>` to `/etc/hosts`). Check with `curl -sk --resolve <rancher_hostname>:443:<ip> https://<rancher_hostname>/ping`, which should print `pong`. Under WSL, `/etc/hosts` is regenerated on restart unless `generateHosts = false` is set in `/etc/wsl.conf`.

## Destroy blocked by the ping check

`tofu destroy` refreshes first, which re-reads every data source, so `data.http.rancher_ping` (60 x 10 s) and `data.http.api_readyz` have to pass again even though nothing is being created. A hostname that no longer resolves, or a runner IP that was removed from the allow lists, blocks the teardown.

1. **Restore reachability (preferred).** Recreate the DNS record (or the `/etc/hosts` entry for standalone) and the allow-list entries, then destroy normally. The Helm uninstall and the `rancher2` providers need the same paths, so this is the only fix that keeps the destroy clean.
2. **Skip the refresh.** `tofu destroy -refresh=false` uses the data source values in state. It gets past the ping check, but it still fails if a provider must contact Rancher or the API during the destroy.
3. **Cluster already destroyed while `module.rancher` still exists in state** (standalone only; it happened before the `depends_on` on the `kubeconfig_secret_name`/`api_server_url` outputs, which order every `rancher` resource before the nodes, and the `depends_on` of `rancher2_setting.telemetry_opt`). Also applies when the cluster is being deleted anyway. `tofu state rm` the `module.rancher` Kubernetes/Helm/`rancher2` resources, then destroy the rest. Deleting the nodes removes the in-cluster objects. Do not `state rm` the Secrets Manager secrets: destroy them, or they stay behind in the account.

In meshStack, the runner has no `/etc/hosts` and no CLI flags. Whether a definition can run a destroy without refresh is not documented here; check the meshStack building block docs before relying on option 2. Option 1 always works.

## Backups missing in S3

[ADR-014](adr/ADR-014-backups-to-s3.md). Check `aws s3 ls s3://<backup_bucket_name>/etcd/` and `.../rancher/`.

- **`AccessDenied` on CreateRole/CreateUser in the run:** the backplane was not re-applied after the backup change, so the runner lacks the bounded IAM permissions or the `rke2-backup-boundary` policy does not exist. Run `tofu apply` in `modules/rke2-cluster/backplane`.
- **No etcd snapshots from servers that existed before ADR-014:** their user data was never re-applied. Add the `etcd-s3*` keys by hand ([operations](operations.md#servers-created-before-adr-014)) or rebuild the servers.
- **etcd upload errors:** `journalctl -u rke2-server | grep -i s3` on a server. `AccessDenied` with a customer managed key means the key policy does not allow the server role, or the backplane's `kms_key_arn` differs.
- **Rancher backup errors:** `kubectl get backups.resources.cattle.io rancher-scheduled -o yaml` (status and conditions) and `kubectl -n cattle-resources-system logs deploy/rancher-backup`. With `kms_key_arn`, the `rancher` building block must use the same key as `rke2-cluster`.
- **`BucketNotEmpty` on delete:** expected with `backup_force_destroy = false`. Keep what you need, empty the bucket, run the delete again ([operations](operations.md#deleting)).

## Let's Encrypt

- HTTP-01 validation needs port 80 reachable from the internet, so `ingress_allowed_cidrs` must include `0.0.0.0/0`, and public DNS must point at `lb_dns_name` with `public_load_balancer = true`.
- Repeated failed orders hit Let's Encrypt rate limits. Check `kubectl -n cattle-system get certificate,order,challenge`, and wait for the limit to reset or temporarily use `tls_source = rancher`.

## Secret scheduled for deletion

Secrets are created with `recovery_window_in_days = 0`, so this only happens when a secret of the same name was deleted by hand with a recovery window. Delete it for good: `aws secretsmanager delete-secret --secret-id <name> --force-delete-without-recovery`, or restore it with `aws secretsmanager restore-secret` and import it.

## PSA violations under the CIS profile

With `hardening_profile = cis`, the `restricted` Pod Security Standard is enforced in every namespace that is not in the exemption list (`/etc/rancher/rke2/rancher-psa.yaml`, see [ADR-011](adr/ADR-011-cis-hardening.md)). Either make the workload compliant, or label its namespace with `pod-security.kubernetes.io/enforce=privileged` (or `baseline`). Changes to the file only reach new servers. Edit existing servers by hand and restart `rke2-server`.

## Plan fails because the cluster is down

When nothing upstream of `data.http.api_readyz` changes, OpenTofu reads it at plan time ([ADR-007](adr/ADR-007-readiness-polling.md)). A broken cluster then fails the plan after about 20 minutes. Recover the cluster first (see [operations](operations.md#disaster-recovery)), or run a targeted plan against the infrastructure resources from a local checkout with the instance's state.

## State cannot be decrypted

The `TF_VAR_state_encryption_passphrase` value on the definition changed or was lost. Encrypted static inputs can also become unreadable when the runner changes. Restore the original passphrase in a new definition version. For a planned change, see [operations](operations.md#state-encryption-passphrase).
