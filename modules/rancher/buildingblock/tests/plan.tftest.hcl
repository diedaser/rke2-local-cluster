# Resources and conditional behaviour, with mocked providers.

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

run "default_install" {
  command = apply

  assert {
    condition     = output.rancher_url == "https://rancher.example.com"
    error_message = "rancher_url must use the hostname."
  }

  assert {
    condition     = local.kube_host == "https://203.0.113.50:6443" && local.kube_client_key == "key"
    error_message = "Kubernetes credentials must come from the Barbican kubeconfig."
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
    condition     = jsondecode(openstack_keymanager_secret_v1.admin.payload).username == "admin"
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
    ingress_class_name = "nginx"
    replicas           = 1
  }

  assert {
    condition     = yamldecode(helm_release.rancher.values[0]).letsEncrypt.email == "platform@example.com"
    error_message = "Let's Encrypt e-mail must be passed to the chart."
  }

  assert {
    condition     = yamldecode(helm_release.rancher.values[0]).ingress.ingressClassName == "nginx"
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
