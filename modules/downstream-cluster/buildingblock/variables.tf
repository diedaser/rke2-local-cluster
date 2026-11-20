# Every variable maps 1:1 to a meshStack input. Keep docs/meshstack-gui-setup.md
# in sync when adding, removing or retyping variables (CONTRIBUTING.md rule 12).

# --- meshStack context ---------------------------------------------------------

variable "workspace_identifier" {
  description = "meshStack workspace identifier (source: Workspace Identifier)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.workspace_identifier))
    error_message = "workspace_identifier must be a meshStack identifier (lowercase letters, digits, dashes)."
  }
}

variable "project_identifier" {
  description = "meshStack project identifier (source: Project Identifier)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.project_identifier))
    error_message = "project_identifier must be a meshStack identifier (lowercase letters, digits, dashes)."
  }
}

variable "building_block_uuid" {
  description = "meshStack building block UUID (source: Building Block UUID). Makes resource and Rancher cluster names unique."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{8,}$", var.building_block_uuid))
    error_message = "building_block_uuid must be a UUID."
  }
}

variable "aws_account_id" {
  description = "AWS account ID of the meshStack tenant (source: Platform Tenant ID). Must match the account of the runner credentials."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12 digit AWS account ID."
  }
}

variable "state_encryption_passphrase" {
  description = "Passphrase for OpenTofu state encryption (ADR-004). Provided as environment variable TF_VAR_state_encryption_passphrase."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.state_encryption_passphrase) >= 16
    error_message = "state_encryption_passphrase must be at least 16 characters."
  }
}

# --- From the parent building block (rancher) ----------------------------------

variable "downstream_credentials_secret_name" {
  description = "Name of the Secrets Manager secret with the Rancher login of meshstack-downstream (source: Parent Building Block Output `downstream_credentials_secret_name`)."
  type        = string

  validation {
    condition     = endswith(var.downstream_credentials_secret_name, "-rancher-downstream")
    error_message = "downstream_credentials_secret_name must be the downstream_credentials_secret_name output of the rancher building block."
  }
}

variable "mgmt_vpc_id" {
  description = "VPC of the management cluster, where the nodes are placed (source: Parent Building Block Output `mgmt_vpc_id` of rancher)."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]{8,17}$", var.mgmt_vpc_id))
    error_message = "mgmt_vpc_id must be the mgmt_vpc_id output of the rancher building block (map rke2-cluster vpc_id into rancher first)."
  }
}

variable "mgmt_private_subnet_ids" {
  description = "Private subnet ID per AZ of the management cluster (source: Parent Building Block Output `mgmt_private_subnet_ids` of rancher). One machine pool per role and AZ."
  type        = map(string)

  validation {
    condition = length(var.mgmt_private_subnet_ids) >= 1 && length(var.mgmt_private_subnet_ids) <= 4 && alltrue([
      for id in values(var.mgmt_private_subnet_ids) : can(regex("^subnet-[0-9a-f]{8,17}$", id))
    ])
    error_message = "mgmt_private_subnet_ids must be the mgmt_private_subnet_ids output of the rancher building block: 1 to 4 subnet IDs keyed by AZ."
  }
}

# --- Platform-controlled inputs ------------------------------------------------

variable "node_driver_access_key_id" {
  description = "Access key ID of the backplane node-driver IAM user (backplane output node_driver_access_key_id). Becomes the Rancher cloud credential."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^(AKIA|ASIA)[A-Z0-9]{16}$", var.node_driver_access_key_id))
    error_message = "node_driver_access_key_id must be an AWS access key ID."
  }
}

variable "node_driver_secret_access_key" {
  description = "Secret access key of the backplane node-driver IAM user (backplane output node_driver_secret_access_key)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.node_driver_secret_access_key) == 40
    error_message = "node_driver_secret_access_key must be a 40 character AWS secret access key."
  }
}

variable "rancher_insecure" {
  description = "Skip TLS verification of the Rancher API. true for Rancher-generated or not yet issued certificates (tls_source rancher/letsEncrypt of the rancher building block); set false with a publicly trusted certificate."
  type        = bool
  default     = true
}

variable "kubernetes_version" {
  description = "RKE2 version of the downstream cluster. Must be offered by the running Rancher (KDM) and stay within the Rancher support matrix (ADR-009)."
  type        = string
  # Rancher v2.15.3 release notes, RKE2 versions: v1.36.5 (default), v1.35.9, v1.34.12.
  default = "v1.36.5+rke2r1"

  validation {
    condition     = can(regex("^v1\\.[0-9]+\\.[0-9]+\\+rke2r[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be a pinned RKE2 release such as v1.36.5+rke2r1."
  }
}

variable "ami_id" {
  description = "Ubuntu 24.04 LTS amd64 AMI ID of the region for the nodes."
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must be an AMI ID such as ami-0123456789abcdef0."
  }
}

variable "kms_key_arn" {
  description = "Optional customer managed KMS key ARN for the nodes' EBS volumes. Must be the backplane's kms_key_arn, which grants the node-driver user. Null uses aws/ebs."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}

variable "root_volume_size_gb" {
  description = "gp3 root volume size per node in GiB."
  type        = number
  default     = 100

  validation {
    condition     = var.root_volume_size_gb >= 40 && var.root_volume_size_gb <= 16384 && floor(var.root_volume_size_gb) == var.root_volume_size_gb
    error_message = "root_volume_size_gb must be an integer between 40 and 16384."
  }
}

# --- User inputs ---------------------------------------------------------------

variable "cluster_name" {
  description = "Cluster name. The Rancher cluster is named <cluster_name>-<short building block id>."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.cluster_name))
    error_message = "cluster_name must be 3-31 lowercase letters, digits or dashes, starting with a letter."
  }
}

variable "control_plane_count" {
  description = "Number of control-plane + etcd nodes: 1 (dev), 3 or 5. String because meshStack offers it as a single select."
  type        = string
  default     = "3"

  validation {
    condition     = contains(["1", "3", "5"], var.control_plane_count)
    error_message = "control_plane_count must be 1, 3 or 5 (etcd needs an odd number)."
  }
}

variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 50 && floor(var.worker_count) == var.worker_count
    error_message = "worker_count must be an integer between 1 and 50."
  }
}

variable "control_plane_instance_type" {
  description = "EC2 instance type of the control-plane + etcd nodes (amd64, matching the AMI)."
  type        = string
  default     = "m7i.xlarge"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.control_plane_instance_type))
    error_message = "control_plane_instance_type must be an EC2 instance type such as m7i.xlarge."
  }
}

variable "worker_instance_type" {
  description = "EC2 instance type of the worker nodes (amd64, matching the AMI)."
  type        = string
  default     = "m7i.large"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.worker_instance_type))
    error_message = "worker_instance_type must be an EC2 instance type such as m7i.large."
  }
}
