# Optional agent pool (default 0). Agents are replaced create-before-destroy
# when their AMI or cloud-init changes, for example on an RKE2 upgrade.

module "agents" {
  source = "../../_shared/node-pool-aws"

  name_prefix         = "${local.prefix}-agent"
  node_count          = var.agent_count
  user_data_base64    = [data.cloudinit_config.node["agent"].rendered]
  instance_type       = local.agent_instance_type
  ami_id              = var.ami_id
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.nodes.id]
  key_name            = var.ssh_key_name
  root_volume_size_gb = var.root_volume_size_gb
  root_volume_iops    = var.root_volume_iops
  kms_key_arn         = var.kms_key_arn
  tags                = merge(local.labels, { "rke2-role" = "agent" })
  replace_on_change   = true

  depends_on = [module.server_init]
}
