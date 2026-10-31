# ADR-004: OpenTofu native state encryption is mandatory

- **Status:** Accepted, 2026-10-16

## Context

State contains CA private keys, the join token, the kubeconfig, the Rancher admin password and token, and, in the backplane, the application credential secret.

## Decision

Every root (`modules/*/buildingblock`, `modules/rke2-cluster/backplane`, `examples/standalone`) declares a `terraform { encryption { ... } }` block:

- key provider `pbkdf2` with `passphrase = var.state_encryption_passphrase`
- method `aes_gcm`
- `state` **and** `plan` both use `enforced = true`

The passphrase is a sensitive variable (at least 16 characters) passed as the environment variable `TF_VAR_state_encryption_passphrase`. In meshStack it is a static, encrypted input provided as Environment. The original design named it `TF_ENCRYPTION_PASSPHRASE`, but HCL cannot read arbitrary environment variables, so it uses the standard `TF_VAR_` mechanism.

## Consequences

- This is the main reason the repository targets OpenTofu rather than Terraform.
- If the passphrase is lost or changed, existing state can no longer be read. Rotation requires an OpenTofu `fallback` block ([operations](../operations.md#state-encryption-passphrase)).
- Use separate passphrases for the `rke2-cluster` and `rancher` definitions.
- Changes to `encryption.tf` require an update to this ADR (CONTRIBUTING.md rule 6).
