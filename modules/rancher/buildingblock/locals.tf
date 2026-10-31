module "naming" {
  source = "../../_shared/naming"

  name                 = "rancher"
  building_block       = "rancher"
  workspace_identifier = var.workspace_identifier
  project_identifier   = var.project_identifier
  building_block_uuid  = var.building_block_uuid
}

locals {
  prefix = module.naming.prefix
  labels = module.naming.labels

  rancher_url = "https://${var.rancher_hostname}"
}
