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
# The parent values (Rancher login secret, management VPC and subnets) are
# read from the local, encrypted state of ../ (data.terraform_remote_state.mgmt),
# standing in for meshStack's Parent Building Block Output mapping. Building
# blocks themselves never use terraform_remote_state (ADR-005).
#
# TF_VAR_state_encryption_passphrase must be the SAME passphrase as for ../:
# OpenTofu's pbkdf2 key provider decrypts a state only with a provider of the
# same name ("passphrase") and passphrase, and this root uses that one
# provider for its own state and for reading ../.
#
# Only the node-driver key comes from the shell (its backplane state has a
# different passphrase); read it in a subshell with the backplane passphrase:
#   export TF_VAR_node_driver_access_key_id=$(cd ../../../modules/rke2-cluster/backplane && TF_VAR_state_encryption_passphrase='<backplane>' tofu output -raw node_driver_access_key_id)
#   export TF_VAR_node_driver_secret_access_key=$(cd ../../../modules/rke2-cluster/backplane && TF_VAR_state_encryption_passphrase='<backplane>' tofu output -raw node_driver_secret_access_key)

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
    # Decrypts ../terraform.tfstate (same key provider name and passphrase).
    remote_state_data_sources {
      default {
        method = method.aes_gcm.default
      }
    }
  }
}

# The management side (rke2-cluster + rancher) from ../. Its path assumes the
# default local backend there; with a backend_override.tf in ../, point this
# data source at the same backend.
data "terraform_remote_state" "mgmt" {
  backend = "local"
  config = {
    path = "${path.module}/../terraform.tfstate"
  }
}

variable "state_encryption_passphrase" {
  description = "State encryption passphrase (TF_VAR_state_encryption_passphrase), the same as for ../. Never commit it."
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

  downstream_credentials_secret_name = data.terraform_remote_state.mgmt.outputs.downstream_credentials_secret_name
  mgmt_vpc_id                        = data.terraform_remote_state.mgmt.outputs.mgmt_vpc_id
  mgmt_private_subnet_ids            = data.terraform_remote_state.mgmt.outputs.mgmt_private_subnet_ids
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
