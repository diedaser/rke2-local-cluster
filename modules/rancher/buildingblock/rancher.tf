resource "kubernetes_namespace_v1" "cattle_system" {
  metadata {
    name   = "cattle-system"
    labels = local.labels
  }

  depends_on = [data.http.api_readyz]

  lifecycle {
    # Rancher adds its own labels and annotations to the namespace.
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

# Bring-your-own certificate (tls_source = secret). The chart expects this
# exact secret name.
resource "kubernetes_secret_v1" "tls_rancher_ingress" {
  count = var.tls_source == "secret" ? 1 : 0

  metadata {
    name      = "tls-rancher-ingress"
    namespace = kubernetes_namespace_v1.cattle_system.metadata[0].name
  }

  type = "kubernetes.io/tls"
  data = {
    "tls.crt" = var.tls_certificate_pem
    "tls.key" = var.tls_private_key_pem
  }
}

resource "helm_release" "rancher" {
  name       = "rancher"
  namespace  = kubernetes_namespace_v1.cattle_system.metadata[0].name
  repository = var.rancher_chart_repository
  chart      = "rancher"
  version    = var.rancher_version

  values = [templatefile("${path.module}/values/rancher.yaml.tftpl", {
    hostname           = var.rancher_hostname
    replicas           = var.replicas
    tls_source         = var.tls_source
    letsencrypt_email  = var.letsencrypt_email
    ingress_class_name = var.ingress_class_name
  })]

  # Single-use password, replaced by rancher2_bootstrap right after install.
  set_sensitive = [{
    name  = "bootstrapPassword"
    value = random_password.bootstrap.result
  }]

  wait    = true
  timeout = 900

  depends_on = [
    helm_release.cert_manager,
    kubernetes_secret_v1.tls_rancher_ingress,
  ]

  lifecycle {
    precondition {
      condition     = var.tls_source != "letsEncrypt" || var.letsencrypt_email != null
      error_message = "letsencrypt_email is required when tls_source = letsEncrypt."
    }
    precondition {
      condition     = var.tls_source != "secret" || (var.tls_certificate_pem != null && var.tls_private_key_pem != null)
      error_message = "tls_certificate_pem and tls_private_key_pem are required when tls_source = secret."
    }
  }
}
