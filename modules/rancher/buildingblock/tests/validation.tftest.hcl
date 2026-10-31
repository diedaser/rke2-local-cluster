# Input validation rules. Mocked providers: never touches real infrastructure.

mock_provider "openstack" {
  mock_data "openstack_identity_auth_scope_v3" {
    defaults = {
      project_id = "0123456789abcdef0123456789abcdef"
    }
  }
  mock_data "openstack_keymanager_secret_v1" {
    defaults = {
      # Test-only kubeconfig with dummy base64 data, no real credentials.
      payload = <<-EOT
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
  mock_resource "openstack_keymanager_secret_v1" {
    defaults = {
      secret_ref = "https://barbican.example.com/v1/secrets/11111111-1111-1111-1111-111111111111"
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
  openstack_project_id        = "0123456789abcdef0123456789abcdef"
  state_encryption_passphrase = "test-passphrase-not-secret"
  kubeconfig_secret_name      = "mgmt-3f2b8c1e-kubeconfig"
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

run "rejects_foreign_project_credentials" {
  command = plan
  variables {
    openstack_project_id = "ffffffffffffffffffffffffffffffff"
  }
  expect_failures = [data.http.api_readyz]
}
