# Server nodes: control plane + etcd (ADR-006).
#
# The first server initialises the cluster; the others join through the
# internal NLB on 9345. Server instances ignore AMI/user data changes (see
# _shared/node-pool-aws) so OpenTofu never silently replaces an etcd member.
# RKE2 upgrades on servers follow docs/operations.md.
#
# CAUTION (CONTRIBUTING.md rule 8): any plan destroying
# module.server_init.aws_instance.pinned[0] or
# module.server_join.aws_instance.pinned[*] removes etcd members. Call it out
# in review.

# Spread: every server on distinct hardware.
resource "aws_placement_group" "servers" {
  name     = "${local.prefix}-servers"
  strategy = "spread"
}

locals {
  server_pool = {
    instance_type       = var.server_instance_type
    ami_id              = var.ami_id
    subnet_ids          = local.private_subnet_ids
    security_group_ids  = [aws_security_group.nodes.id, aws_security_group.servers.id]
    placement_group     = aws_placement_group.servers.name
    key_name            = var.ssh_key_name
    root_volume_size_gb = var.root_volume_size_gb
    root_volume_iops    = var.root_volume_iops
    kms_key_arn         = var.kms_key_arn
    tags                = merge(local.labels, { "rke2-role" = "server" })
  }
}

module "server_init" {
  source = "../../_shared/node-pool-aws"

  name_prefix         = "${local.prefix}-server"
  node_count          = 1
  user_data_base64    = [data.cloudinit_config.node["server_init"].rendered]
  instance_type       = local.server_pool.instance_type
  ami_id              = local.server_pool.ami_id
  subnet_ids          = local.server_pool.subnet_ids
  security_group_ids  = local.server_pool.security_group_ids
  placement_group     = local.server_pool.placement_group
  key_name            = local.server_pool.key_name
  root_volume_size_gb = local.server_pool.root_volume_size_gb
  root_volume_iops    = local.server_pool.root_volume_iops
  kms_key_arn         = local.server_pool.kms_key_arn
  tags                = local.server_pool.tags
  replace_on_change   = false

  depends_on = [
    aws_route.private_nat,
    aws_route_table_association.private,
    aws_vpc_security_group_ingress_rule.nodes_self,
    aws_vpc_security_group_ingress_rule.etcd,
    aws_vpc_security_group_egress_rule.nodes_all,
  ]
}

module "server_join" {
  source = "../../_shared/node-pool-aws"

  name_prefix         = "${local.prefix}-server"
  index_offset        = 1
  node_count          = local.join_server_count
  user_data_base64    = [data.cloudinit_config.node["server_join"].rendered]
  instance_type       = local.server_pool.instance_type
  ami_id              = local.server_pool.ami_id
  subnet_ids          = local.server_pool.subnet_ids
  security_group_ids  = local.server_pool.security_group_ids
  placement_group     = local.server_pool.placement_group
  key_name            = local.server_pool.key_name
  root_volume_size_gb = local.server_pool.root_volume_size_gb
  root_volume_iops    = local.server_pool.root_volume_iops
  kms_key_arn         = local.server_pool.kms_key_arn
  tags                = local.server_pool.tags
  replace_on_change   = false

  depends_on = [module.server_init]
}
