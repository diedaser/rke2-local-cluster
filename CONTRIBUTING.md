# Contributing

Rules for everyone changing this repository. Code comments and ADRs cite them as "CONTRIBUTING.md rule N". Design decisions are in [docs/adr](docs/adr/README.md).

## Rules

1. **Never** add `local-exec`, `remote-exec`, `null_resource` with shell, `external` data sources, or anything that needs binaries in the runner (ADR-002).
2. **Never** commit state, `.tfvars` with real values, kubeconfigs, keys, or passwords. Mark every secret variable and output `sensitive = true`.
3. Every new variable needs a `description`, a `type`, a `validation` block where a constraint exists, and a corresponding row in `docs/meshstack-gui-setup.md`.
4. Pin provider versions with `~>` on minor. Do not loosen existing pins without being asked.
5. Keep `buildingblock/` runnable by meshStack with **only** inputs and environment variables. No interactive prompts and no reliance on the local filesystem beyond the module.
6. Any change touching `pki.tf`, `secrets.tf`, or `encryption.tf` requires an ADR update and a note in the PR.
7. Changes to RKE2/Rancher/cert-manager versions must cite the Rancher support matrix version row.
8. Use `moved {}` blocks when renaming or restructuring resources. Never force replacement of server nodes or the LB silently. Call out any plan that destroys `openstack_compute_instance_v2.server[*]` or etcd-bearing resources.
9. Run `./scripts/validate-all.sh` before declaring a task done. Add or extend a `tofu test` for every new validation rule or conditional resource.
10. Prefer small, single-purpose PRs. Update `README.md` (terraform-docs) and the BB's `summary.md.tftpl` when outputs change.
11. Never add a `backend` block to a `buildingblock/`, and never expose a secret as an output. meshStack shows outputs in plaintext.
12. When a variable, its type, or an output changes, update `docs/meshstack-gui-setup.md` in the same PR, because the meshStack definition must be changed to match.
13. When unsure about a meshStack-specific behavior (input types, assignment types, state handling), say so and point to the meshStack docs rather than guessing.

## Network requirements

Enforced by the security groups in `modules/rke2-cluster/buildingblock/network.tf`.

| Port | Proto | Source | Purpose |
|---|---|---|---|
| 6443 | TCP | LB, nodes, admin CIDRs, meshStack runner egress IPs | Kubernetes API |
| 9345 | TCP | LB, nodes | RKE2 supervisor / node registration |
| 10250 | TCP | nodes | kubelet |
| 2379-2381 | TCP | server nodes | etcd client, peer, metrics |
| 8472 | UDP | nodes | Canal/Flannel VXLAN |
| 9099 | TCP | nodes | Canal health checks |
| 30000-32767 | TCP/UDP | nodes (optional public) | NodePorts |
| 80, 443 | TCP | LB, user CIDRs | Ingress / Rancher UI |
| 22 | TCP | bastion / admin CIDRs only | Break-glass SSH (never used by OpenTofu) |

The **meshStack runner must reach the Kubernetes API (6443) and Rancher (443) through the LB.** Otherwise the `rancher` BB cannot apply.
