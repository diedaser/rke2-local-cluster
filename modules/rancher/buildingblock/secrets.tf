# Cluster access comes from AWS Secrets Manager, written by the parent
# building block. The Rancher admin credentials go back to Secrets Manager;
# only their name and ARN are output (ADR-012). Changes here require an ADR update (CONTRIBUTING.md rule 6).

data "aws_secretsmanager_secret_version" "kubeconfig" {
  secret_id = var.kubeconfig_secret_name

  lifecycle {
    postcondition {
      condition     = can(yamldecode(self.secret_string).clusters[0].cluster.server)
      error_message = "Secret ${var.kubeconfig_secret_name} does not contain a kubeconfig."
    }
  }
}

locals {
  kubeconfig = yamldecode(data.aws_secretsmanager_secret_version.kubeconfig.secret_string)

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

resource "aws_secretsmanager_secret" "admin" {
  name        = "${local.prefix}-rancher-admin"
  description = "Rancher admin credentials for ${local.rancher_url} (meshStack building block ${var.building_block_uuid})."
  kms_key_id  = var.kms_key_arn

  # Worthless once Rancher is gone; immediate deletion allows re-creation
  # under the same name.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "admin" {
  secret_id = aws_secretsmanager_secret.admin.id
  secret_string = jsonencode({
    url      = local.rancher_url
    username = "admin"
    password = rancher2_bootstrap.admin.password
    token    = rancher2_bootstrap.admin.token
  })
}
