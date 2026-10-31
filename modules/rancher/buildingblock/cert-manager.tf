resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_version

  values = [templatefile("${path.module}/values/cert-manager.yaml.tftpl", {})]

  wait          = true
  wait_for_jobs = true
  timeout       = 600
  atomic        = true

  depends_on = [data.http.api_readyz]
}
