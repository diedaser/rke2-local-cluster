# ADR-007: Readiness is polled, not slept

- **Status:** Accepted, 2026-10-16

## Context

Downstream steps (publishing the kubeconfig, Helm releases, Rancher bootstrap) need a working endpoint. Fixed sleeps are either too short or wasteful.

## Decision

Use the `http` data source with a `retry` block and a `postcondition` on `status_code`:

| Data source | URL | Auth / TLS | Retry |
|---|---|---|---|
| `rke2-cluster` `data.http.api_readyz` | `<api_server_url>/readyz` | admin client cert, verified against `server-ca` | 120 x 10 s (cloud-init, RKE2, NLB target registration) |
| `rancher` `data.http.api_readyz` | `<api_server_url>/readyz` | credentials from the Secrets Manager kubeconfig | 30 x 10 s |
| `rancher` `data.http.rancher_ping` | `https://<rancher_hostname>/ping`, expects `pong` | `insecure = true` | 60 x 10 s |

Downstream resources `depends_on` these data sources: the kubeconfig secret version, cert-manager, the `cattle-system` namespace and `rancher2_bootstrap`. `time_sleep` is used only where no endpoint exists. There is currently no such case.

## Consequences

- If nothing upstream changes, the data source is read **at plan time**. A cluster that is down then fails the plan after the retries run out, even when the apply was meant to fix it ([troubleshooting](../troubleshooting.md#plan-fails-because-the-cluster-is-down)).
- The `rancher` readiness check also verifies that the runner can reach 6443. The ping verifies DNS and the path to 443.
