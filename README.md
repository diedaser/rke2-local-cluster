# RKE2 + Rancher `local` cluster as meshStack Building Blocks

OpenTofu building blocks that provision a production-grade **RKE2** cluster on
**AWS EC2 (Ubuntu 24.04)** and install **Rancher** on it as its `local` (management) cluster.
They are ordered through the meshStack marketplace and run by meshStack's
building block runner.

| Building block | Path | What it does |
|---|---|---|
| `rke2-cluster` | [`modules/rke2-cluster/buildingblock`](modules/rke2-cluster/buildingblock) | VPC (private + public subnets per AZ, NAT), security groups, internal NLB (6443/9345) + optional public NLB (6443/80/443), 1/3/5 servers + optional agents on EC2, RKE2 via cloud-init, OpenTofu-generated cluster PKI, `/readyz` polling, admin kubeconfig in AWS Secrets Manager |
| `rancher` | [`modules/rancher/buildingblock`](modules/rancher/buildingblock) | cert-manager, Rancher Helm release, admin bootstrap, telemetry opt-out, `/ping` polling, admin credentials in AWS Secrets Manager |
| `downstream-cluster` | [`modules/downstream-cluster/buildingblock`](modules/downstream-cluster/buildingblock) | RKE2 workload cluster provisioned by Rancher with the EC2 node driver: own VPC (private nodes, NAT, no peering), one machine pool per role and AZ, login as the least-privilege Rancher user `meshstack-downstream` ([ADR-015](docs/adr/ADR-015-downstream-clusters.md)) |

`rancher` depends on `rke2-cluster` and reads the cluster's kubeconfig from
AWS Secrets Manager using the parent's `kubeconfig_secret_name` output. No secret is ever a
meshStack output.

Default versions (Rancher support matrix row **Rancher v2.15.2**, local cluster
RKE2 v1.34 to v1.36):

| Component | Version |
|---|---|
| OpenTofu | 1.12.8 (`.opentofu-version`) |
| RKE2 | v1.36.6+rke2r1 |
| Rancher chart | 2.15.2 (`rancher/rancher2` provider ~> 15.1.0) |
| cert-manager | v1.21.2 |
| rancher-backup chart | 110.0.3+up11.0.4 (Rancher 2.15 line) |

Backups: etcd snapshots and encrypted Rancher backups go to a per-cluster S3
bucket, 10 kept each by default ([ADR-014](docs/adr/ADR-014-backups-to-s3.md)).

## Ordering in meshStack

1. Platform team: run the [backplane](modules/rke2-cluster/backplane) once and
   create both definitions as described in
   [docs/meshstack-gui-setup.md](docs/meshstack-gui-setup.md).
2. In a project with a tenant on the AWS platform, order **RKE2 Cluster**:
   cluster name, server count, instance type, admin CIDRs. A run takes 10 to 25 minutes.
3. Create a DNS CNAME (or Route 53 alias) for the Rancher hostname pointing at output `lb_dns_name`.
4. Order **Rancher Manager** on the same tenant: hostname and TLS source.
5. Open `rancher_url`. The admin password is in AWS Secrets Manager (`admin_secret_name`).

Delete in reverse order: `rancher` first, then `rke2-cluster`.

## Repository layout

```
modules/
  rke2-cluster/{buildingblock,backplane,meshstack}
  rancher/{buildingblock,backplane,meshstack}
  downstream-cluster/{buildingblock,backplane,meshstack}
  _shared/{naming,node-pool-aws}        # internal child modules
examples/standalone/                     # rke2-cluster + rancher without meshStack (dev)
examples/standalone/downstream/          # one downstream-cluster on top, own state
docs/                                    # ADRs, GUI setup, operations, troubleshooting
scripts/                                 # validate-all.sh, fetch-kubeconfig.sh, fetch-rancher-admin.sh
```

## Development

```bash
./scripts/validate-all.sh   # fmt -check, init -backend=false, validate, tflint, tofu test, guard rails
```

Tests use `mock_provider` and never touch real infrastructure. End-to-end tests
against a dev AWS account use [`examples/standalone`](examples/standalone/main.tf)
(two-phase apply, see the comment in its `main.tf`).

Rules for contributors (human or AI) are in [CONTRIBUTING.md](CONTRIBUTING.md). Design
decisions are in [docs/adr](docs/adr/README.md). Day-2 tasks are in
[docs/operations.md](docs/operations.md), and known failure modes in
[docs/troubleshooting.md](docs/troubleshooting.md).

## Known limitations

- One AWS account and region per definition: the runner's IAM access key belongs
  to one account, its policy is restricted to one region, and both building
  blocks refuse to run against another tenant account
  ([ADR-013](docs/adr/ADR-013-tenant-project-scope.md)).
- Each cluster creates its own VPC with a single NAT gateway. An existing VPC
  cannot be reused yet, and losing the NAT gateway's AZ cuts node egress.
- Client IPs are not preserved through the NLBs
  ([ADR-006](docs/adr/ADR-006-fixed-registration-address.md)).
- Nodes run amd64 Ubuntu 24.04 from a pinned `ami_id`; the instance type
  architecture must match the AMI.
- Server nodes are never replaced by OpenTofu on image or cloud-init changes.
  RKE2 upgrades on servers follow the rolling procedure in
  [docs/operations.md](docs/operations.md).
- The readiness data sources run during `plan` when nothing upstream changes, so a
  plan fails while the cluster or Rancher is down.
- Nodes need outbound internet access to `get.rke2.io` and the RKE2 artifacts
  through the NAT gateway (or a mirror via `rke2_install_script_url`). Air-gapped installs are not covered.
