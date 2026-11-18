# The admin kubeconfig goes to AWS Secrets Manager; only its name and ARN
# leave the building block (ADR-012). The child building block `rancher`
# reads the secret by name.
# Changes here require an ADR update (CONTRIBUTING.md rule 6).

locals {
  kubeconfig = templatefile("${path.module}/templates/kubeconfig.yaml.tftpl", {
    cluster_name    = var.cluster_name
    api_server_url  = local.api_server_url
    ca_cert_pem     = tls_self_signed_cert.ca["server-ca"].cert_pem
    client_cert_pem = tls_locally_signed_cert.admin.cert_pem
    client_key_pem  = tls_private_key.admin.private_key_pem
  })

  kubeconfig_secret_name = "${local.prefix}-kubeconfig"
}

resource "aws_secretsmanager_secret" "kubeconfig" {
  name        = local.kubeconfig_secret_name
  description = "Admin kubeconfig of RKE2 cluster ${var.cluster_name} (meshStack building block ${var.building_block_uuid})."
  kms_key_id  = var.kms_key_arn

  # The kubeconfig is worthless once the cluster is gone. Immediate deletion
  # lets the same building block instance be re-created under the same name.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "kubeconfig" {
  secret_id     = aws_secretsmanager_secret.kubeconfig.id
  secret_string = local.kubeconfig

  # Publish credentials only for a cluster that is actually reachable.
  depends_on = [data.http.api_readyz]
}
