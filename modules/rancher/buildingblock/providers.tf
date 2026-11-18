# AWS credentials and region come from the environment (AWS_ACCESS_KEY_ID,
# AWS_SECRET_ACCESS_KEY, AWS_REGION), only to read and write Secrets Manager
# secrets. Kubernetes and Helm use the admin kubeconfig read from Secrets
# Manager (secrets.tf). No provider reads files from the runner.

provider "aws" {
  default_tags {
    tags = local.labels
  }
}

# Checked against the meshStack tenant (aws_account_id), see readiness.tf.
data "aws_caller_identity" "current" {}

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
