# ADR-012: Secrets go to a secret store, outputs carry references only

- **Status:** Accepted, 2026-10-16

## Context

meshStack does not support sensitive outputs. Every mapped output is visible in meshPanel.

## Decision

- `rke2-cluster` writes the admin kubeconfig to Barbican (`openstack_keymanager_secret_v1.kubeconfig`, named `<prefix>-kubeconfig`). It outputs `kubeconfig_secret_name` and `kubeconfig_secret_ref`.
- The Barbican data source cannot look up a secret by `secret_ref`, only by name and filters. The `rancher` input is therefore **`kubeconfig_secret_name`**, mapped from the parent output. This deviates from the original interface design, which named `kubeconfig_secret_ref`. The `rancher` building block validates that the name ends in `-kubeconfig` and that the payload is a kubeconfig.
- `rancher` stores the admin URL, username, password and API token as JSON in `<prefix>-rancher-admin`, and outputs `admin_secret_ref` and `admin_secret_name`.
- Barbican secrets are immutable. A changed payload (for example a renewed admin certificate) replaces the secret, so both secrets use `create_before_destroy`. Because the child resolves the secret by name on every run, it always finds the current one.
- Building blocks have **no** Terraform `sensitive` outputs at all. `scripts/validate-all.sh` enforces this. Break-glass access uses `scripts/fetch-kubeconfig.sh`, which reads Barbican with the `openstack` CLI instead of a state output.

## Consequences

- The runner credentials need permission to create secrets in Barbican (often the `creator` role).
- Names must be unique per project. The UUID-based prefix ([ADR-010](ADR-010-meshstack-identity-naming.md)) guarantees this. Leftover duplicates cause "more than one secret" errors.
- Changes to `secrets.tf` require an update to this ADR (CONTRIBUTING.md rule 6).
