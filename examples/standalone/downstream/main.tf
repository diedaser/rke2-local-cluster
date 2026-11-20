# Adds one downstream cluster (ADR-015) to the Rancher of ../ (examples/
# standalone), for development and end-to-end tests. Its nodes go into the
# management VPC and private subnets of ../. Own root module and own state,
# like a separate meshStack building block run: the module carries its own
# provider blocks, so it cannot be switched on and off with count inside
# ../main.tf, and a separate state keeps the node costs out of every
# management-cluster test.
#
# Order (meshStack enforces none of it, so neither does this example):
#
#   1. cd .. && tofu apply -target=module.rke2_cluster && tofu apply
#   2. cd downstream && tofu apply
#   ...
#   3. cd downstream && tofu destroy        # BEFORE destroying ../
#   4. cd .. && tofu destroy
#
# Destroying ../ first fails on the management subnets, which still hold the
# downstream instances, after Rancher (their owner) is already gone. Clean
# them up by tag in that case (docs/troubleshooting.md, "Downstream cluster").
#
# Inputs from elsewhere, exported in the shell (never in a file):
#   export TF_VAR_state_encryption_passphrase=...      # may differ from ../
#   export TF_VAR_downstream_credentials_secret_name=$(tofu -chdir=.. output -raw downstream_credentials_secret_name)
#   export TF_VAR_mgmt_vpc_id=$(tofu -chdir=.. output -raw mgmt_vpc_id)
#   export TF_VAR_mgmt_private_subnet_ids=$(tofu -chdir=.. output -json mgmt_private_subnet_ids)
#   export TF_VAR_node_driver_access_key_id=$(tofu -chdir=../../../modules/rke2-cluster/backplane output -raw node_driver_access_key_id)
#   export TF_VAR_node_driver_secret_access_key=$(tofu -chdir=../../../modules/rke2-cluster/backplane output -raw node_driver_secret_access_key)
# The backplane reads need its own TF_VAR_state_encryption_passphrase; run
# them in a subshell if it differs.

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
  description = "AWS account ID the AWS_* credentials belong to (same account as ../)."
  type        = string
}

variable "ami_id" {
  description = "Ubuntu 24.04 amd64 AMI ID for the region."
  type        = string
}

variable "downstream_credentials_secret_name" {
  description = "Output downstream_credentials_secret_name of ../ (TF_VAR_downstream_credentials_secret_name)."
  type        = string
}

variable "mgmt_vpc_id" {
  description = "Output mgmt_vpc_id of ../ (TF_VAR_mgmt_vpc_id)."
  type        = string
}

variable "mgmt_private_subnet_ids" {
  description = "Output mgmt_private_subnet_ids of ../ (TF_VAR_mgmt_private_subnet_ids, JSON map)."
  type        = map(string)
}

variable "node_driver_access_key_id" {
  description = "Backplane output node_driver_access_key_id (TF_VAR_node_driver_access_key_id). Never commit it."
  type        = string
  sensitive   = true
}

variable "node_driver_secret_access_key" {
  description = "Backplane output node_driver_secret_access_key (TF_VAR_node_driver_secret_access_key). Never commit it."
  type        = string
  sensitive   = true
}

variable "cluster_name" {
  description = "Downstream cluster name."
  type        = string
  default     = "dev-apps"
}

variable "control_plane_count" {
  description = "1 for a cheap smoke test, 3 for an HA control plane."
  type        = string
  default     = "1"
}

variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 1
}

module "downstream_cluster" {
  source = "../../../modules/downstream-cluster/buildingblock"

  # Stand-ins for the identifiers meshStack injects (same as ../).
  workspace_identifier        = "dev"
  project_identifier          = "standalone"
  building_block_uuid         = "00000000-0000-4000-8000-000000000003"
  aws_account_id              = var.aws_account_id
  state_encryption_passphrase = var.state_encryption_passphrase

  downstream_credentials_secret_name = var.downstream_credentials_secret_name
  mgmt_vpc_id                        = var.mgmt_vpc_id
  mgmt_private_subnet_ids            = var.mgmt_private_subnet_ids
  node_driver_access_key_id          = var.node_driver_access_key_id
  node_driver_secret_access_key      = var.node_driver_secret_access_key

  cluster_name                = var.cluster_name
  ami_id                      = var.ami_id
  control_plane_count         = var.control_plane_count
  worker_count                = var.worker_count
  control_plane_instance_type = "m7i.large"
  worker_instance_type        = "m7i.large"
}

output "rancher_cluster_url" {
  description = "The downstream cluster in the Rancher UI."
  value       = module.downstream_cluster.rancher_cluster_url
}

output "cluster_name" {
  description = "Name of the cluster in Rancher."
  value       = module.downstream_cluster.cluster_name
}

output "summary" {
  description = "Cluster summary."
  value       = module.downstream_cluster.summary
}
