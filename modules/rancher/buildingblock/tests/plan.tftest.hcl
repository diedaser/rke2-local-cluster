# Resources and conditional behaviour, with mocked providers.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_data "aws_region" {
    defaults = {
      region = "eu-central-1"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_secretsmanager_secret_version" {
    defaults = {
      # Test-only kubeconfig with dummy base64 data, no real credentials.
      secret_string = <<-EOT
        apiVersion: v1
        kind: Config
        clusters:
          - name: mgmt
            cluster:
              server: https://203.0.113.50:6443
              certificate-authority-data: Y2E=
        users:
          - name: mgmt-admin
            user:
              client-certificate-data: Y2VydA==
              client-key-data: a2V5
        contexts:
          - name: mgmt
            context:
              cluster: mgmt
              user: mgmt-admin
        current-context: mgmt
      EOT
    }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn    = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:rancher-9a8b7c6d-rancher-admin-AbCdEf"
      region = "eu-central-1"
    }
  }
}

mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code   = 200
      response_body = "pong"
    }
  }
}

mock_provider "helm" {}
mock_provider "kubernetes" {}
mock_provider "rancher2" {
  alias = "bootstrap"
}
mock_provider "rancher2" {
  alias = "admin"
}

variables {
  workspace_identifier        = "platform"
  project_identifier          = "rancher-mgmt"
  building_block_uuid         = "9a8b7c6d-1234-4abc-9def-0123456789ab"
  aws_account_id              = "123456789012"
  state_encryption_passphrase = "test-passphrase-not-secret"
  kubeconfig_secret_name      = "mgmt-3f2b8c1e-kubeconfig"
  backup_bucket_name          = "rke2-backup-3f2b8c1e-123456789012"
  api_server_url              = "https://203.0.113.50:6443"
  rancher_hostname            = "rancher.example.com"
}

run "default_install" {
  command = apply

  assert {
    condition     = output.rancher_url == "https://rancher.example.com"
    error_message = "rancher_url must use the hostname."
  }

  assert {
    condition     = local.kube_host == "https://203.0.113.50:6443" && local.kube_client_key == "key"
    error_message = "Kubernetes credentials must come from the Secrets Manager kubeconfig."
  }

  assert {
    condition     = helm_release.rancher.version == "2.15.2" && helm_release.cert_manager.version == "v1.21.2"
    error_message = "Chart versions must be pinned to the defaults."
  }

  assert {
    condition     = yamldecode(helm_release.rancher.values[0]).ingress.tls.source == "rancher"
    error_message = "Default TLS source must be rancher."
  }

  assert {
    condition     = yamldecode(helm_release.rancher.values[0]).replicas == 3
    error_message = "Default replicas must be 3."
  }

  assert {
    condition     = yamldecode(helm_release.cert_manager.values[0]).crds.enabled == true
    error_message = "cert-manager must install its CRDs."
  }

  assert {
    condition     = length(kubernetes_secret_v1.tls_rancher_ingress) == 0
    error_message = "No TLS secret unless tls_source = secret."
  }

  assert {
    condition     = output.admin_secret_name == "rancher-9a8b7c6d-rancher-admin"
    error_message = "Admin secret name must derive from the BB UUID."
  }

  assert {
    condition     = jsondecode(aws_secretsmanager_secret_version.admin.secret_string).username == "admin"
    error_message = "Admin secret must hold the admin credentials."
  }

  assert {
    condition     = rancher2_setting.telemetry_opt.value == "out"
    error_message = "Telemetry must be opted out."
  }
}

run "letsencrypt" {
  command = apply

  variables {
    tls_source         = "letsEncrypt"
    letsencrypt_email  = "platform@example.com"
    ingress_class_name = "traefik"
    replicas           = 1
  }

  assert {
    condition     = yamldecode(helm_release.rancher.values[0]).letsEncrypt.email == "platform@example.com"
    error_message = "Let's Encrypt e-mail must be passed to the chart."
  }

  assert {
    condition     = yamldecode(helm_release.rancher.values[0]).ingress.ingressClassName == "traefik"
    error_message = "Ingress class must be passed to the chart."
  }

  assert {
    condition     = yamldecode(helm_release.rancher.values[0]).antiAffinity == "preferred"
    error_message = "Single replica uses preferred anti-affinity."
  }
}

run "bring_your_own_certificate" {
  command = apply

  variables {
    tls_source          = "secret"
    tls_certificate_pem = "-----BEGIN CERTIFICATE-----\nZHVtbXk=\n-----END CERTIFICATE-----\n"
    tls_private_key_pem = "-----BEGIN PRIVATE KEY-----\nZHVtbXk=\n-----END PRIVATE KEY-----\n"
  }

  assert {
    condition     = length(kubernetes_secret_v1.tls_rancher_ingress) == 1
    error_message = "tls_source = secret must create the tls-rancher-ingress secret."
  }

  assert {
    condition     = kubernetes_secret_v1.tls_rancher_ingress[0].metadata[0].name == "tls-rancher-ingress"
    error_message = "The chart expects the secret tls-rancher-ingress."
  }
}

run "backups" {
  command = apply

  assert {
    condition = yamldecode(helm_release.rancher_backup.values[0]).s3 == {
      enabled                   = true
      credentialSecretName      = "rancher-backup-s3-credentials"
      credentialSecretNamespace = "cattle-resources-system"
      bucketName                = "rke2-backup-3f2b8c1e-123456789012"
      folder                    = "rancher"
      region                    = "eu-central-1"
      endpoint                  = "s3.eu-central-1.amazonaws.com"
    }
    error_message = "rancher-backup must default to the rancher/ prefix of the cluster's backup bucket."
  }

  assert {
    condition     = helm_release.rancher_backup.version == "110.0.3+up11.0.4" && helm_release.rancher_backup_crd.version == helm_release.rancher_backup.version
    error_message = "rancher-backup and its CRD chart must use the same pinned version."
  }

  assert {
    condition = yamldecode(helm_release.rancher_backup_schedule.values[0]) == {
      name                       = "rancher-scheduled"
      resourceSetName            = "rancher-resource-set-full"
      schedule                   = "0 3 * * *"
      retentionCount             = 10
      encryptionConfigSecretName = "rancher-backup-encryption"
    }
    error_message = "The recurring backup must be encrypted, full, daily and keep 10."
  }

  assert {
    condition     = aws_iam_user.rancher_backup.path == "/rke2-backup/"
    error_message = "The backup IAM user must live under /rke2-backup/ (backplane IAM scope)."
  }

  assert {
    condition     = aws_iam_user.rancher_backup.permissions_boundary == "arn:aws:iam::123456789012:policy/rke2/rke2-backup-boundary"
    error_message = "The backup IAM user must carry the backplane permissions boundary, or the runner is denied CreateUser."
  }

  assert {
    condition     = kubernetes_secret_v1.backup_s3_credentials.data.accessKey == aws_iam_access_key.rancher_backup.id
    error_message = "The operator must use the dedicated IAM user's key."
  }

  assert {
    condition = (
      yamldecode(aws_secretsmanager_secret_version.backup_encryption.secret_string).kind == "EncryptionConfiguration" &&
      kubernetes_secret_v1.backup_encryption.data["encryption-provider-config.yaml"] == aws_secretsmanager_secret_version.backup_encryption.secret_string
    )
    error_message = "The in-cluster encryption config must be escrowed unchanged in Secrets Manager."
  }

  assert {
    condition     = aws_secretsmanager_secret.backup_encryption.recovery_window_in_days == 30
    error_message = "The backup encryption key must survive an accidental delete for 30 days."
  }

  assert {
    condition     = output.backup_encryption_secret_name == aws_secretsmanager_secret.backup_encryption.name
    error_message = "The escrow secret name must be output (name only, ADR-012)."
  }
}

run "backup_retention_override" {
  command = plan

  variables {
    rancher_backup_retention = 30
    rancher_backup_schedule  = "0 */12 * * *"
  }

  assert {
    condition     = yamldecode(helm_release.rancher_backup_schedule.values[0]).retentionCount == 30 && yamldecode(helm_release.rancher_backup_schedule.values[0]).schedule == "0 */12 * * *"
    error_message = "Schedule and retention inputs must reach the Backup resource."
  }
}

run "downstream_access" {
  command = apply

  assert {
    condition     = rancher2_user.downstream.username == "meshstack-downstream" && rancher2_user.downstream.enabled
    error_message = "The downstream-cluster building block needs its own enabled Rancher user."
  }

  assert {
    condition     = toset([for b in rancher2_global_role_binding.downstream : b.global_role_id]) == toset(["user-base", "clusters-create"])
    error_message = "The downstream user must get exactly user-base and clusters-create, never admin or the Standard User role."
  }

  assert {
    condition     = alltrue([for b in rancher2_global_role_binding.downstream : b.user_id == rancher2_user.downstream.id])
    error_message = "Both role bindings must target the downstream user."
  }

  assert {
    condition = (
      jsondecode(aws_secretsmanager_secret_version.downstream.secret_string).url == "https://rancher.example.com" &&
      jsondecode(aws_secretsmanager_secret_version.downstream.secret_string).username == "meshstack-downstream" &&
      jsondecode(aws_secretsmanager_secret_version.downstream.secret_string).password == random_password.downstream.result
    )
    error_message = "The downstream secret must carry url, username and the user's password."
  }

  assert {
    condition     = output.downstream_credentials_secret_name == aws_secretsmanager_secret.downstream.name
    error_message = "Only the secret name may be output (ADR-012)."
  }
}

run "backup_encryption_immediate_delete" {
  command = plan

  variables {
    backup_encryption_recovery_window_days = 0
  }

  assert {
    condition     = aws_secretsmanager_secret.backup_encryption.recovery_window_in_days == 0
    error_message = "backup_encryption_recovery_window_days must reach the secret."
  }
}
