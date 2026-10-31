# RKE2 + Rancher `local` cluster as meshStack Building Blocks

OpenTofu building blocks that provision a production-grade **RKE2** cluster on
**OpenStack** and install **Rancher** on it as its `local` (management) cluster.
They are ordered through the meshStack marketplace and run by meshStack's
building block runner.

| Building block | Path | What it does |
|---|---|---|
| `rke2-cluster` | [`modules/rke2-cluster/buildingblock`](modules/rke2-cluster/buildingblock) | Network, security groups, Octavia LB (6443/9345/80/443) with floating IP, 1/3/5 servers + optional agents, RKE2 via cloud-init, OpenTofu-generated cluster PKI, `/readyz` polling, admin kubeconfig in Barbican |
| `rancher` | [`modules/rancher/buildingblock`](modules/rancher/buildingblock) | cert-manager, Rancher Helm release, admin bootstrap, telemetry opt-out, `/ping` polling, admin credentials in Barbican |

`rancher` depends on `rke2-cluster` and reads the cluster's kubeconfig from
Barbican using the parent's `kubeconfig_secret_name` output. No secret is ever a
meshStack output.

Default versions (Rancher support matrix row **Rancher v2.15.2**, local cluster
RKE2 v1.34 to v1.36):

| Component | Version |
|---|---|
| OpenTofu | 1.12.8 (`.opentofu-version`) |
| RKE2 | v1.35.9+rke2r1 |
| Rancher chart | 2.15.2 (`rancher/rancher2` provider ~> 15.1.0) |
| cert-manager | v1.21.2 |

## Ordering in meshStack

1. Platform team: run the [backplane](modules/rke2-cluster/backplane) once and
   create both definitions as described in
   [docs/meshstack-gui-setup.md](docs/meshstack-gui-setup.md).
2. In a project with a tenant on the OpenStack platform, order **RKE2 Cluster**:
   cluster name, server count, flavor, admin CIDRs. A run takes 10 to 20 minutes.
3. Create a DNS A record for the Rancher hostname pointing at output `lb_ip`.
4. Order **Rancher Manager** on the same tenant: hostname and TLS source.
5. Open `rancher_url`. The admin password is in Barbican (`admin_secret_ref`).

Delete in reverse order: `rancher` first, then `rke2-cluster`.

## Repository layout

```
modules/
  rke2-cluster/{buildingblock,backplane,meshstack}
  rancher/{buildingblock,backplane,meshstack}
  _shared/{naming,node-pool-openstack}   # internal child modules
examples/standalone/                     # both BBs without meshStack (dev)
docs/                                    # ADRs, GUI setup, operations, troubleshooting
scripts/                                 # validate-all.sh, fetch-kubeconfig.sh
```

## Development

```bash
./scripts/validate-all.sh   # fmt -check, init -backend=false, validate, tflint, tofu test, guard rails
```

Tests use `mock_provider` and never touch real infrastructure. End-to-end tests
against a dev project use [`examples/standalone`](examples/standalone/main.tf)
(two-phase apply, see the comment in its `main.tf`).

Rules for contributors (human or AI) are in [CONTRIBUTING.md](CONTRIBUTING.md). Design
decisions are in [docs/adr](docs/adr/README.md). Day-2 tasks are in
[docs/operations.md](docs/operations.md), and known failure modes in
[docs/troubleshooting.md](docs/troubleshooting.md).

## Known limitations

- One OpenStack project per definition: the runner's application credential is
  project-scoped, and both building blocks refuse to run against another tenant
  project ([ADR-013](docs/adr/ADR-013-tenant-project-scope.md)).
- Server nodes are never replaced by OpenTofu on image or cloud-init changes.
  RKE2 upgrades on servers follow the rolling procedure in
  [docs/operations.md](docs/operations.md).
- The readiness data sources run during `plan` when nothing upstream changes, so a
  plan fails while the cluster or Rancher is down.
- Nodes need outbound internet access to `get.rke2.io` and the RKE2 artifacts
  (or a mirror via `rke2_install_script_url`). Air-gapped installs are not covered.
