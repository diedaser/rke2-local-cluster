# ADR-003: OpenTofu-generated cluster PKI

- **Status:** Accepted, 2026-10-16

## Context

Without SSH ([ADR-002](ADR-002-no-ssh-no-local-exec.md)), OpenTofu cannot read `/etc/rancher/rke2/rke2.yaml` from a node. RKE2 supports custom CA certificates: if the CA files exist in `/var/lib/rancher/rke2/server/tls/` when the first server starts for the first time, RKE2 skips CA generation.

## Decision

`pki.tf` generates the CA set with the `tls` provider:

- `server-ca`, `client-ca`, `request-header-ca`, `etcd/server-ca`, `etcd/peer-ca`: ECDSA P-256, self-signed, valid 10 years (`local.ca_validity_hours = 87600`). `tls_self_signed_cert.ca` ignores changes to `subject`, `allowed_uses` and `validity_period_hours`, so a CA never rotates by accident.
- `service.key`: RSA 2048, used to sign service account tokens. It has no certificate.
- cloud-init writes these files **only on the first server**, using base64 `write_files` entries so the bytes on disk match `cert_pem` exactly. Joining servers receive the CAs from the cluster datastore.
- Admin client certificate: CN `meshstack-admin`, O `system:masters`, signed by `client-ca`. Validity is `admin_cert_validity_hours` (default 8760), and `early_renewal_hours = min(720, floor(validity / 4))`.
- Join token (`token.tf`): the first server uses the bare random secret. Joining servers and agents use `K10<sha256(server-ca cert_pem)>::server:<secret>`, which pins the cluster CA on join.
- The kubeconfig is built from a template with the API URL, `server-ca` and the admin certificate.

## Consequences

- CA private keys and the join token live in state, so state encryption is mandatory ([ADR-004](ADR-004-state-encryption.md)).
- CA keys, the token and the PSA config are also in the first server's Nova user data, which anyone with read access to the project can see.
- CA rotation is a manual procedure ([operations](../operations.md#ca-rotation)).
- Re-applying within the last 30 days of validity (or the last quarter of a shorter validity) renews the admin certificate and replaces the Barbican kubeconfig secret.
- The token hash must match what RKE2 serves on `/cacerts`. If `server-ca.crt` on the first server is changed, nodes can no longer join ([troubleshooting](../troubleshooting.md#joining-nodes-token-ca-hash-does-not-match)).
- Changes to `pki.tf` require an update to this ADR (CONTRIBUTING.md rule 6).
