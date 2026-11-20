module "naming" {
  source = "../../_shared/naming"

  name                 = var.cluster_name
  building_block       = "downstream-cluster"
  workspace_identifier = var.workspace_identifier
  project_identifier   = var.project_identifier
  building_block_uuid  = var.building_block_uuid
}

locals {
  prefix = module.naming.prefix
  labels = module.naming.labels
  region = data.aws_region.current.region

  # Unique in Rancher per building block instance (ADR-010).
  rancher_cluster_name = local.prefix
}
