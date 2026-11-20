# Composes both building blocks without meshStack, for development and
# end-to-end tests against a dev AWS account.
#
# The rancher module configures its Kubernetes/Helm providers from a secret
# the cluster module creates, so the first apply is two-phase:
#
#   tofu apply -target=module.rke2_cluster
#   tofu apply
#
# meshStack does not need this: there the two modules are separate building
# blocks with separate runs (ADR-001).
#
# Backend: local by default; for a shared dev state, put an S3 backend into a
# git-ignored backend_override.tf (ADR-005).

terraform {
  required_version = ">= 1.8"

  encryption {
    key_provider "pbkdf2" "passphrase" {
      passphrase = var.state_encryption_passphrase
    }
    method "aes_gcm" "default" {
      keys = key_provider.pbkdf2.passphrase
    }
    state {
      method   = method.aes_gcm.default
      enforced = true
    }
    plan {
      method   = method.aes_gcm.default
      enforced = true
    }
  }
}

variable "state_encryption_passphrase" {
  description = "State encryption passphrase (TF_VAR_state_encryption_passphrase). Never commit it."
  type        = string
  sensitive   = true
}

variable "aws_account_id" {
  description = "AWS account ID the AWS_* credentials belong to."
  type        = string
}

variable "cluster_name" {
  description = "Cluster name."
  type        = string
  default     = "dev-mgmt"
}

variable "server_count" {
  description = "3 (default) for an HA etcd quorum like production, 1 for a cheaper smoke test."
  type        = string
  default     = "3"
}

variable "server_instance_type" {
  description = "EC2 instance type for server nodes."
  type        = string
  default     = "m7i.xlarge"
}

variable "ami_id" {
  description = "Ubuntu 24.04 AMI ID for the region (see the ami_id input of rke2-cluster)."
  type        = string
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the API; include your workstation's egress IP."
  type        = list(string)
}

variable "rancher_hostname" {
  description = "Rancher FQDN. Null (default) uses the public NLB DNS name, which resolves without a DNS record or /etc/hosts entry and follows the NLB across rebuilds. Set a real FQDN only together with a CNAME to the lb_dns_name output."
  type        = string
  default     = null
}

locals {
  # Stand-ins for the identifiers meshStack injects.
  workspace_identifier = "dev"
  project_identifier   = "standalone"
}

module "rke2_cluster" {
  source = "../../modules/rke2-cluster/buildingblock"

  workspace_identifier        = local.workspace_identifier
  project_identifier          = local.project_identifier
  building_block_uuid         = "00000000-0000-4000-8000-000000000001"
  aws_account_id              = var.aws_account_id
  state_encryption_passphrase = var.state_encryption_passphrase

  cluster_name         = var.cluster_name
  server_count         = var.server_count
  server_instance_type = var.server_instance_type
  ami_id               = var.ami_id
  api_allowed_cidrs    = var.api_allowed_cidrs
  hardening_profile    = "none"

  # Dev: the backups go with the cluster. Production keeps them (default false).
  backup_force_destroy = true
}

module "rancher" {
  source = "../../modules/rancher/buildingblock"

  workspace_identifier        = local.workspace_identifier
  project_identifier          = local.project_identifier
  building_block_uuid         = "00000000-0000-4000-8000-000000000002"
  aws_account_id              = var.aws_account_id
  state_encryption_passphrase = var.state_encryption_passphrase

  kubeconfig_secret_name = module.rke2_cluster.kubeconfig_secret_name
  api_server_url         = module.rke2_cluster.api_server_url
  backup_bucket_name     = module.rke2_cluster.backup_bucket_name
  rancher_hostname       = coalesce(var.rancher_hostname, module.rke2_cluster.lb_dns_name)
  replicas               = tonumber(var.server_count)
}

output "api_server_url" {
  description = "Kubernetes API URL."
  value       = module.rke2_cluster.api_server_url
}

output "lb_dns_name" {
  description = "Client NLB DNS name. Rancher's hostname unless rancher_hostname is set; then point its CNAME here."
  value       = module.rke2_cluster.lb_dns_name
}

output "rancher_url" {
  description = "Rancher UI."
  value       = module.rancher.rancher_url
}

output "backup_bucket_name" {
  description = "S3 bucket with etcd snapshots (etcd/) and Rancher backups (rancher/)."
  value       = module.rke2_cluster.backup_bucket_name
}

output "summary" {
  description = "Cluster summary."
  value       = module.rke2_cluster.summary
}
