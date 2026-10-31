# OpenTofu native state and plan encryption (ADR-004). No backend block here:
# meshStack injects its built-in HTTP backend (ADR-005).
#
# The passphrase arrives as the environment variable
# TF_VAR_state_encryption_passphrase (static, encrypted meshStack input).
terraform {
  encryption {
    key_provider "pbkdf2" "passphrase" {
      passphrase = var.state_encryption_passphrase
    }

    method "aes_gcm" "default" {
      keys = key_provider.pbkdf2.passphrase
    }

    state {
      method   = method.aes_gcm.default
      enforced = true
    }

    plan {
      method   = method.aes_gcm.default
      enforced = true
    }
  }
}
