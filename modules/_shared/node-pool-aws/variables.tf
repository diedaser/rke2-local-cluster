variable "name_prefix" {
  description = "Prefix of the instance names. Instances are tagged `Name = <prefix>-NN`."
  type        = string
}

variable "node_count" {
  description = "Number of nodes in the pool."
  type        = number

  validation {
    condition     = var.node_count >= 0 && floor(var.node_count) == var.node_count
    error_message = "node_count must be a non-negative integer."
  }
}

variable "index_offset" {
  description = "Number added to the instance index in names and subnet round-robin (lets the joining servers continue after the first one)."
  type        = number
  default     = 0
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

variable "ami_id" {
  description = "AMI ID (Ubuntu 24.04 LTS with cloud-init)."
  type        = string
}

variable "user_data_base64" {
  description = "Base64 encoded (optionally gzipped) cloud-init user data per node. With fewer entries than nodes, entries are reused round-robin (one entry = same data on all nodes)."
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(var.user_data_base64) > 0
    error_message = "user_data_base64 needs at least one entry."
  }
}

variable "subnet_ids" {
  description = "Subnets the nodes are placed in, round-robin by index. Use one subnet per AZ to spread nodes across AZs."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids needs at least one subnet."
  }
}

variable "security_group_ids" {
  description = "Security groups applied to the nodes."
  type        = list(string)
}

variable "placement_group" {
  description = "Optional placement group name (spread strategy for etcd members)."
  type        = string
  default     = null
}

variable "key_name" {
  description = "Optional EC2 key pair name for break-glass SSH. OpenTofu never uses SSH (ADR-002)."
  type        = string
  default     = null
}

variable "iam_instance_profile" {
  description = "Optional IAM instance profile name. Changing it re-associates the profile in place; the instance is not replaced."
  type        = string
  default     = null
}

variable "root_volume_size_gb" {
  description = "Size of the gp3 root volume in GiB."
  type        = number
  default     = 100
}

variable "root_volume_iops" {
  description = "Provisioned IOPS of the gp3 root volume (etcd is latency sensitive)."
  type        = number
  default     = 3000
}

variable "root_volume_throughput" {
  description = "Provisioned throughput of the gp3 root volume in MiB/s."
  type        = number
  default     = 125
}

variable "kms_key_arn" {
  description = "Optional KMS key ARN for root volume encryption. Null uses the AWS managed key aws/ebs."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags set on every instance and root volume (in addition to the provider default tags)."
  type        = map(string)
  default     = {}
}

variable "replace_on_change" {
  description = "true: replace nodes (create before destroy) when AMI or user data change. false: ignore such changes (use for etcd members)."
  type        = bool
  default     = false
}
