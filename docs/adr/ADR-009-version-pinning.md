# ADR-009: Strict version pinning, support-matrix driven

- **Status:** Accepted, 2026-10-16

## Decision

The following are all pinned:

- OpenTofu itself (`.opentofu-version`)
- every provider (`~> X.Y.0`)
- RKE2 (`rke2_version`, validated against `^v1.N.N+rke2rN$`)
- the Rancher chart (`rancher_version`)
- the cert-manager chart (`cert_manager_version`)

Defaults form a combination from the Rancher support matrix:

| Component | Default | Matrix row |
|---|---|---|
| Rancher | `2.15.2` | Rancher v2.15.2: local cluster RKE2 v1.34 to v1.36 |
| RKE2 | `v1.35.9+rke2r1` | within v1.34 to v1.36 |
| cert-manager | `v1.21.2` | supported cert-manager release |

## Consequences

- Upgrades are PRs that change one component at a time and cite the matrix row (CONTRIBUTING.md rule 7).
