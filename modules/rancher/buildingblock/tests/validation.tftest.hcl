# Input validation rules. Mocked providers: never touches real infrastructure.

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

run "valid_defaults" {
  command = plan
}

run "rejects_bad_hostname" {
  command = plan
  variables {
    rancher_hostname = "Rancher_UI"
  }
  expect_failures = [var.rancher_hostname]
}

run "rejects_unknown_tls_source" {
  command = plan
  variables {
    tls_source = "acme"
  }
  expect_failures = [var.tls_source]
}

run "rejects_bad_email" {
  command = plan
  variables {
    tls_source        = "letsEncrypt"
    letsencrypt_email = "not-an-email"
  }
  expect_failures = [var.letsencrypt_email]
}

run "requires_email_for_letsencrypt" {
  command = plan
  variables {
    tls_source = "letsEncrypt"
  }
  expect_failures = [helm_release.rancher]
}

run "requires_cert_for_secret" {
  command = plan
  variables {
    tls_source = "secret"
  }
  expect_failures = [helm_release.rancher]
}

run "rejects_unpinned_rancher_version" {
  command = plan
  variables {
    rancher_version = "latest"
  }
  expect_failures = [var.rancher_version]
}

run "rejects_v_prefixed_rancher_version" {
  command = plan
  variables {
    rancher_version = "v2.15.2"
  }
  expect_failures = [var.rancher_version]
}

run "rejects_unpinned_cert_manager_version" {
  command = plan
  variables {
    cert_manager_version = "1.x"
  }
  expect_failures = [var.cert_manager_version]
}

run "rejects_too_many_replicas" {
  command = plan
  variables {
    replicas = 5
  }
  expect_failures = [var.replicas]
}

run "rejects_bad_api_url" {
  command = plan
  variables {
    api_server_url = "http://203.0.113.50"
  }
  expect_failures = [var.api_server_url]
}

run "rejects_foreign_secret_name" {
  command = plan
  variables {
    kubeconfig_secret_name = "something-else"
  }
  expect_failures = [var.kubeconfig_secret_name]
}

run "rejects_foreign_account_credentials" {
  command = plan
  variables {
    aws_account_id = "999999999999"
  }
  expect_failures = [data.http.api_readyz]
}

run "rejects_bad_account_id" {
  command = plan
  variables {
    aws_account_id = "12345"
  }
  expect_failures = [var.aws_account_id]
}

run "rejects_bad_kms_key" {
  command = plan
  variables {
    kms_key_arn = "alias/my-key"
  }
  expect_failures = [var.kms_key_arn]
}

run "rejects_foreign_backup_bucket" {
  command = plan
  variables {
    backup_bucket_name = "my-random-bucket"
  }
  expect_failures = [var.backup_bucket_name]
}

run "rejects_zero_backup_retention" {
  command = plan
  variables {
    rancher_backup_retention = 0
  }
  expect_failures = [var.rancher_backup_retention]
}

run "rejects_bad_backup_schedule" {
  command = plan
  variables {
    rancher_backup_schedule = "@daily"
  }
  expect_failures = [var.rancher_backup_schedule]
}

run "rejects_unpinned_backup_chart" {
  command = plan
  variables {
    rancher_backup_chart_version = "110.0.3"
  }
  expect_failures = [var.rancher_backup_chart_version]
}

run "rejects_short_recovery_window" {
  command = plan
  variables {
    backup_encryption_recovery_window_days = 3
  }
  expect_failures = [var.backup_encryption_recovery_window_days]
}

run "rejects_foreign_vpc_id" {
  command = plan
  variables {
    mgmt_vpc_id = "my-vpc"
  }
  expect_failures = [var.mgmt_vpc_id]
}

run "rejects_foreign_subnet_ids" {
  command = plan
  variables {
    mgmt_private_subnet_ids = { "eu-central-1a" = "10.100.0.0/19" }
  }
  expect_failures = [var.mgmt_private_subnet_ids]
}
