# Cluster access comes from Barbican, written by the parent building block.
# The Rancher admin credentials go back to Barbican; only their reference is
# output (ADR-012). Changes here require an ADR update (CONTRIBUTING.md rule 6).

data "openstack_keymanager_secret_v1" "kubeconfig" {
  name        = var.kubeconfig_secret_name
  secret_type = "opaque"

  lifecycle {
    postcondition {
      condition     = can(yamldecode(self.payload).clusters[0].cluster.server)
      error_message = "Barbican secret ${var.kubeconfig_secret_name} does not contain a kubeconfig."
    }
  }
}

locals {
  kubeconfig = yamldecode(data.openstack_keymanager_secret_v1.kubeconfig.payload)

  kube_host                   = local.kubeconfig.clusters[0].cluster.server
  kube_cluster_ca_certificate = base64decode(local.kubeconfig.clusters[0].cluster["certificate-authority-data"])
  kube_client_certificate     = base64decode(local.kubeconfig.users[0].user["client-certificate-data"])
  kube_client_key             = base64decode(local.kubeconfig.users[0].user["client-key-data"])
}

resource "random_password" "bootstrap" {
  length  = 32
  special = false
}

resource "random_password" "admin" {
  length      = 32
  special     = true
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
  # Characters safe in JSON, YAML and shells.
  override_special = "!#%*+-.:=?@_"
}

resource "openstack_keymanager_secret_v1" "admin" {
  name                 = "${local.prefix}-rancher-admin"
  secret_type          = "opaque"
  payload_content_type = "text/plain"
  metadata             = local.labels
  payload = jsonencode({
    url      = local.rancher_url
    username = "admin"
    password = rancher2_bootstrap.admin.password
    token    = rancher2_bootstrap.admin.token
  })

  lifecycle {
    create_before_destroy = true
  }
}
