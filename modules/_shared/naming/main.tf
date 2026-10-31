# Consistent names and labels derived from meshStack identifiers (ADR-010).
# Pure function module: no providers, no resources.

terraform {
  required_version = ">= 1.8"
}

variable "name" {
  description = "Base name of the resources (for example the user-provided cluster name)."
  type        = string
}

variable "building_block" {
  description = "Name of the building block that owns the resources, for example `rke2-cluster`."
  type        = string
}

variable "workspace_identifier" {
  description = "meshStack workspace identifier."
  type        = string
}

variable "project_identifier" {
  description = "meshStack project identifier."
  type        = string
}

variable "building_block_uuid" {
  description = "meshStack building block UUID. Used to make names unique within an OpenStack project."
  type        = string
}

locals {
  # 8 hex chars of the BB UUID keep names short but unique per instance.
  short_id = substr(replace(lower(var.building_block_uuid), "-", ""), 0, 8)
  prefix   = "${var.name}-${local.short_id}"

  labels = {
    "meshstack-workspace"      = var.workspace_identifier
    "meshstack-project"        = var.project_identifier
    "meshstack-building-block" = var.building_block_uuid
    "managed-by"               = "opentofu"
    "building-block"           = var.building_block
  }
}

output "prefix" {
  description = "Unique resource name prefix: `<name>-<first 8 chars of BB UUID>`."
  value       = local.prefix
}

output "short_id" {
  description = "Short unique suffix derived from the building block UUID."
  value       = local.short_id
}

output "labels" {
  description = "Labels as a map, for resources supporting key/value metadata (Nova metadata, Kubernetes labels)."
  value       = local.labels
}

output "tags" {
  description = "Labels rendered as `key=value` strings, for OpenStack resources supporting only string tags."
  value       = sort([for k, v in local.labels : "${k}=${v}"])
}
