# The admin kubeconfig goes to Barbican; only references leave the building
# block (ADR-012). The child building block `rancher` looks the secret up by
# name, because the Barbican data source cannot look up by reference.
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

resource "openstack_keymanager_secret_v1" "kubeconfig" {
  name                 = local.kubeconfig_secret_name
  secret_type          = "opaque"
  payload              = local.kubeconfig
  payload_content_type = "text/plain"
  metadata             = local.labels

  # Barbican secrets are immutable: a renewed admin certificate replaces the
  # secret. Create the new one first so readers never find no secret.
  lifecycle {
    create_before_destroy = true
  }

  # Publish credentials only for a cluster that is actually reachable.
  depends_on = [data.http.api_readyz]
}
