module "naming" {
  source = "../../_shared/naming"

  name                 = var.cluster_name
  building_block       = "rke2-cluster"
  workspace_identifier = var.workspace_identifier
  project_identifier   = var.project_identifier
  building_block_uuid  = var.building_block_uuid
}

locals {
  prefix = module.naming.prefix
  labels = module.naming.labels
  tags   = module.naming.tags

  server_count      = tonumber(var.server_count)
  join_server_count = local.server_count - 1
  agent_flavor      = coalesce(var.agent_flavor, var.server_flavor)

  # Address the nodes use to register (private VIP) and the address clients
  # use to reach the API (floating IP if assigned).
  lb_vip_address = openstack_lb_loadbalancer_v2.this.vip_address
  lb_public_ip   = var.assign_floating_ip ? openstack_networking_floatingip_v2.lb[0].address : local.lb_vip_address

  registration_url = "https://${local.lb_vip_address}:9345"
  api_server_url   = "https://${local.lb_public_ip}:6443"

  tls_sans = distinct(compact(concat(
    [local.lb_vip_address, local.lb_public_ip],
    var.api_extra_sans,
  )))

  # Octavia listener allow lists. The subnet CIDR is always included so nodes
  # can reach the VIP; it also keeps the lists non-empty (empty = allow all).
  api_allowed_cidrs     = distinct(concat(var.api_allowed_cidrs, var.runner_egress_cidrs, [var.subnet_cidr]))
  ingress_allowed_cidrs = distinct(concat(var.ingress_allowed_cidrs, var.runner_egress_cidrs, [var.subnet_cidr]))

  cis_enabled = var.hardening_profile == "cis"

  # Kubernetes node labels mirror the meshStack labels (ADR-010).
  node_labels = [for k, v in local.labels : "${k}=${v}"]
}
