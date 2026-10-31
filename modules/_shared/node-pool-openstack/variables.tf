variable "name_prefix" {
  description = "Prefix of the instance names. Instances are named `<prefix>-NN`."
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
  description = "Number added to the instance index in names (lets the joining servers continue after the first one)."
  type        = number
  default     = 0
}

variable "flavor_name" {
  description = "Nova flavor name."
  type        = string
}

variable "image_name" {
  description = "Glance image name. The most recent image with this name is used."
  type        = string
}

variable "user_data" {
  description = "cloud-init user data per node. With fewer entries than nodes, entries are reused round-robin (one entry = same data on all nodes)."
  type        = list(string)
  sensitive   = true

  validation {
    condition     = length(var.user_data) > 0
    error_message = "user_data needs at least one entry."
  }
}

variable "network_id" {
  description = "ID of the Neutron network the nodes attach to."
  type        = string
}

variable "security_group_names" {
  description = "Names of the security groups applied to the nodes."
  type        = list(string)
}

variable "server_group_id" {
  description = "Optional Nova server group ID (anti-affinity)."
  type        = string
  default     = null
}

variable "key_pair" {
  description = "Optional Nova key pair name for break-glass SSH. OpenTofu never uses SSH (ADR-002)."
  type        = string
  default     = null
}

variable "availability_zones" {
  description = "Optional list of availability zones, assigned round-robin."
  type        = list(string)
  default     = []
}

variable "boot_volume_size_gb" {
  description = "Size of the boot volume in GiB."
  type        = number
  default     = 100
}

variable "boot_volume_type" {
  description = "Optional Cinder volume type for the boot volume (use a low-latency SSD type for etcd)."
  type        = string
  default     = null
}

variable "metadata" {
  description = "Nova metadata (labels) set on every instance."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "String tags set on every instance."
  type        = list(string)
  default     = []
}

variable "replace_on_change" {
  description = "true: replace nodes (create before destroy) when image or user_data change. false: ignore such changes (use for etcd members)."
  type        = bool
  default     = false
}
