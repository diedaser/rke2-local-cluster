# OpenTofu native state and plan encryption (ADR-004). The backplane runs outside meshStack;
# configure its backend in a git-ignored backend_override.tf.
#
# The passphrase arrives as the environment variable
# TF_VAR_state_encryption_passphrase (never commit it).
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
