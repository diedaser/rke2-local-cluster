# OpenStack credentials come from the environment (OS_*), only to read and
# write Barbican secrets; the default openstack provider configuration reads
# them, so it has no block here. Kubernetes and Helm use the admin kubeconfig
# read from Barbican (secrets.tf). No provider reads files from the runner.

data "openstack_identity_auth_scope_v3" "current" {
  name = "current"
}

provider "kubernetes" {
  host                   = local.kube_host
  cluster_ca_certificate = local.kube_cluster_ca_certificate
  client_certificate     = local.kube_client_certificate
  client_key             = local.kube_client_key
}

provider "helm" {
  kubernetes = {
    host                   = local.kube_host
    cluster_ca_certificate = local.kube_cluster_ca_certificate
    client_certificate     = local.kube_client_certificate
    client_key             = local.kube_client_key
  }
}

# TLS verification is skipped for the Rancher API unless the certificate comes
# from a bring-your-own secret: with `rancher` the CA is generated in-cluster
# during this run, and with `letsEncrypt` the certificate may not be issued yet
# when bootstrap starts. The bootstrap password is single-use and replaced
# immediately. See ADR-008.
provider "rancher2" {
  alias     = "bootstrap"
  api_url   = local.rancher_url
  bootstrap = true
  insecure  = var.tls_source != "secret"
  timeout   = "300s"
}

provider "rancher2" {
  alias     = "admin"
  api_url   = local.rancher_url
  token_key = rancher2_bootstrap.admin.token
  insecure  = var.tls_source != "secret"
  timeout   = "300s"
}
