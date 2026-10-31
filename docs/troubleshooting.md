# Troubleshooting

| Symptom | Section |
|---|---|
| `rke2-cluster` run times out on `/readyz` | [API readiness timeout](#api-readiness-timeout) |
| "credentials are scoped to project ..." | [Project mismatch](#credentials-scoped-to-the-wrong-project) |
| 403 creating a Barbican secret | [Barbican 403](#barbican-403) |
| 403 creating the load balancer | [Octavia 403](#octavia-403) |
| Listener error about `allowed_cidrs` | [allowed_cidrs not supported](#listener-allowed_cidrs-not-supported) |
| Joining servers or agents never appear | [Token CA hash](#joining-nodes-token-ca-hash-does-not-match) |
| `rancher` run fails on `/ping` | [Rancher ping fails](#rancher-ping-fails) |
| Let's Encrypt certificate not issued | [Let's Encrypt](#lets-encrypt) |
| "more than one secret" | [Duplicate Barbican secrets](#duplicate-barbican-secrets) |
| Pods rejected by PodSecurity | [PSA violations](#psa-violations-under-the-cis-profile) |
| Plan fails although nothing changed | [Cluster down at plan time](#plan-fails-because-the-cluster-is-down) |
| State cannot be decrypted | [State decryption](#state-cannot-be-decrypted) |

## API readiness timeout

`data.http.api_readyz` retries 90 x 10 s. If the API never answers:

1. **The runner cannot reach 6443.** Add the runner's egress IPs to `runner_egress_cidrs`. Keep `assign_floating_ip = true` unless the runner sits inside the network. If the cluster is private, use a self-hosted runner. Test from a host with the same egress: `curl -k https://<lb_ip>:6443/readyz` should return 401 or `ok`, not a timeout.
2. **cloud-init or the RKE2 install failed.** Open the server's console log (`openstack console log show <server>`), or check `/var/log/cloud-init-output.log`, `journalctl -u rke2-server` and `cloud-init status --long` on the node. Typical causes:
   - The image has no `curl` or no cloud-init.
   - Nodes cannot reach `get.rke2.io` or GitHub (no router/SNAT, DNS). Set `dns_nameservers`, or set `rke2_install_script_url` to a reachable mirror.
   - Under the CIS profile, the `etcd` user or the sysctls are missing because of a non-standard image.
3. **LB members unhealthy.** Run `openstack loadbalancer member list <pool>`. Members only turn healthy once RKE2 listens.

## Credentials scoped to the wrong project

The precondition compares the credentials' project with `openstack_project_id` (Platform Tenant ID). The application credential belongs to a different project than the tenant. Use a definition whose credential matches the tenant's project ([ADR-013](adr/ADR-013-tenant-project-scope.md)).

## Barbican 403

The application credential lacks permission to create secrets. Many clouds require the `creator` role for Barbican. Recreate the credential with `roles = ["member", "creator"]` in `modules/rke2-cluster/backplane`. Application credential roles cannot be changed in place.

## Octavia 403

Legacy Octavia policies require `load-balancer_member`. Add it to the backplane `roles` and recreate the credential.

## Listener allowed_cidrs not supported

Listener `allowed_cidrs` needs Octavia API 2.12 or later, and some providers (older OVN provider drivers) reject it. Upgrade Octavia or use the `amphora` provider (`lb_provider`). Do not drop the allow lists: without them, 6443 and 9345 are open to anyone who can reach the floating IP.

## Joining nodes: token CA hash does not match

Joining servers and agents use `K10<sha256(server-ca cert_pem)>::server:<secret>`. `journalctl -u rke2-server` (or `rke2-agent`) shows `token CA hash does not match`. Causes:

- `/var/lib/rancher/rke2/server/tls/server-ca.crt` on the first server was changed or regenerated, for example because RKE2 started before cloud-init wrote the CA files, so RKE2 generated its own.
- `tls_self_signed_cert.ca["server-ca"]` was replaced in state, so new nodes carry a different hash.

Compare `sha256sum server-ca.crt` on server 0 with the hash in the token. Fix the underlying cause; see CA rotation in [operations](operations.md#ca-rotation).

## Rancher ping fails

`data.http.rancher_ping` expects `pong` from `https://<rancher_hostname>/ping`.

- **DNS:** the hostname must resolve, from the runner, to the cluster's `lb_ip` output. Create the record before running `rancher`.
- **443 not allowed:** the runner egress IPs must be in the LB's 80/443 allow list (`ingress_allowed_cidrs`, plus `runner_egress_cidrs`, which is appended automatically).
- **Rancher pods not ready:** `kubectl -n cattle-system get pods` and `kubectl -n cattle-system logs deploy/rancher`.

## Let's Encrypt

- HTTP-01 validation needs port 80 reachable from the internet, so `ingress_allowed_cidrs` must include `0.0.0.0/0`, and public DNS must point at `lb_ip`.
- Repeated failed orders hit Let's Encrypt rate limits. Check `kubectl -n cattle-system get certificate,order,challenge`, and wait for the limit to reset or temporarily use `tls_source = rancher`.

## Duplicate Barbican secrets

The Barbican data source fails when more than one secret matches `kubeconfig_secret_name`. Names include the building block UUID, so duplicates usually come from an interrupted create-before-destroy. List them with `openstack secret list --name <name>`, keep the newest (it matches the `kubeconfig_secret_ref` output), and delete the rest.

## PSA violations under the CIS profile

With `hardening_profile = cis`, the `restricted` Pod Security Standard is enforced in every namespace that is not in the exemption list (`/etc/rancher/rke2/rancher-psa.yaml`, see [ADR-011](adr/ADR-011-cis-hardening.md)). Either make the workload compliant, or label its namespace with `pod-security.kubernetes.io/enforce=privileged` (or `baseline`). Changes to the file only reach new servers. Edit existing servers by hand and restart `rke2-server`.

## Plan fails because the cluster is down

When nothing upstream of `data.http.api_readyz` changes, OpenTofu reads it at plan time ([ADR-007](adr/ADR-007-readiness-polling.md)). A broken cluster then fails the plan after about 15 minutes. Recover the cluster first (see [operations](operations.md#disaster-recovery)), or run a targeted plan against the infrastructure resources from a local checkout with the instance's state.

## State cannot be decrypted

The `TF_VAR_state_encryption_passphrase` value on the definition changed or was lost. Encrypted static inputs can also become unreadable when the runner changes. Restore the original passphrase in a new definition version. For a planned change, see [operations](operations.md#state-encryption-passphrase).
