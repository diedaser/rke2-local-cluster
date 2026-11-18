module "naming" {
  source = "../../_shared/naming"

  name                 = var.cluster_name
  building_block       = "rke2-cluster"
  workspace_identifier = var.workspace_identifier
  project_identifier   = var.project_identifier
  building_block_uuid  = var.building_block_uuid
}

locals {
  prefix   = module.naming.prefix
  short_id = module.naming.short_id
  labels   = module.naming.labels

  server_count        = tonumber(var.server_count)
  join_server_count   = local.server_count - 1
  agent_instance_type = coalesce(var.agent_instance_type, var.server_instance_type)

  # Nodes register through the internal NLB. Clients use the public NLB if
  # there is one, otherwise the internal NLB as well (ADR-006).
  internal_lb_dns = aws_lb.internal.dns_name
  client_lb_dns   = var.public_load_balancer ? aws_lb.public[0].dns_name : local.internal_lb_dns

  registration_url = "https://${local.internal_lb_dns}:9345"
  api_server_url   = "https://${local.client_lb_dns}:6443"

  tls_sans = distinct(compact(concat(
    [local.internal_lb_dns, local.client_lb_dns],
    var.api_extra_sans,
  )))

  # Client allow lists. The runner always needs 6443 and 443 (CONTRIBUTING.md,
  # network requirements).
  api_client_cidrs     = distinct(concat(var.api_allowed_cidrs, var.runner_egress_cidrs))
  ingress_client_cidrs = distinct(concat(var.ingress_allowed_cidrs, var.runner_egress_cidrs))

  cis_enabled = var.hardening_profile == "cis"

  # Kubernetes node labels mirror the meshStack labels (ADR-010).
  node_labels = [for k, v in local.labels : "${k}=${v}"]
}
