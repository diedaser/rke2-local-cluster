# ADR-001: Two building blocks instead of one

- **Status:** Accepted, 2026-10-16

## Context

The Helm, Kubernetes and rancher2 providers need a working API endpoint and credentials at plan time. Those do not exist until the cluster is created. A single root module would need `-target` applies or two-phase workarounds, which the meshStack runner does not support.

## Decision

Split the work into two meshStack building blocks:

- `rke2-cluster` (parent): network, load balancer, VMs, PKI, kubeconfig in Barbican.
- `rancher` (child, depends on `rke2-cluster`): cert-manager, Rancher, admin bootstrap.

The child receives non-secret references from the parent through the meshStack input source "Parent Building Block Output" (`kubeconfig_secret_name`, `api_server_url`) and resolves the credential from Barbican ([ADR-012](ADR-012-secrets-in-barbican.md)).

## Consequences

- Each building block plans cleanly in one run.
- Cluster and Rancher can be upgraded independently.
- `examples/standalone/`, which composes both modules in one root, needs a two-phase apply (`-target=module.rke2_cluster` first). This only affects development.
