# Composes both building blocks without meshStack, for development and
# end-to-end tests against a dev OpenStack project.
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

variable "openstack_project_id" {
  description = "OpenStack project ID the OS_* credentials are scoped to."
  type        = string
}

variable "cluster_name" {
  description = "Cluster name."
  type        = string
  default     = "dev-mgmt"
}

variable "server_count" {
  description = "1 for dev, 3 for production-like tests."
  type        = string
  default     = "1"
}

variable "server_flavor" {
  description = "Nova flavor for server nodes."
  type        = string
}

variable "image_name" {
  description = "Glance image name."
  type        = string
}

variable "external_network_name" {
  description = "External network for the router and floating IP."
  type        = string
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the API; include your workstation's egress IP."
  type        = list(string)
}

variable "rancher_hostname" {
  description = "Rancher FQDN. Create the DNS record for the lb_ip output between the two apply phases."
  type        = string
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
  openstack_project_id        = var.openstack_project_id
  state_encryption_passphrase = var.state_encryption_passphrase

  cluster_name          = var.cluster_name
  server_count          = var.server_count
  server_flavor         = var.server_flavor
  image_name            = var.image_name
  external_network_name = var.external_network_name
  api_allowed_cidrs     = var.api_allowed_cidrs
  hardening_profile     = "none"
}

module "rancher" {
  source = "../../modules/rancher/buildingblock"

  workspace_identifier        = local.workspace_identifier
  project_identifier          = local.project_identifier
  building_block_uuid         = "00000000-0000-4000-8000-000000000002"
  openstack_project_id        = var.openstack_project_id
  state_encryption_passphrase = var.state_encryption_passphrase

  kubeconfig_secret_name = module.rke2_cluster.kubeconfig_secret_name
  api_server_url         = module.rke2_cluster.api_server_url
  rancher_hostname       = var.rancher_hostname
  replicas               = tonumber(var.server_count)
}

output "api_server_url" {
  description = "Kubernetes API URL."
  value       = module.rke2_cluster.api_server_url
}

output "lb_ip" {
  description = "Point the Rancher DNS record here."
  value       = module.rke2_cluster.lb_ip
}

output "rancher_url" {
  description = "Rancher UI."
  value       = module.rancher.rancher_url
}

output "summary" {
  description = "Cluster summary."
  value       = module.rke2_cluster.summary
}
