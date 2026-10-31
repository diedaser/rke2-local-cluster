# Optional agent pool (default 0). Agents are replaced create-before-destroy
# when their image or cloud-init changes, for example on an RKE2 upgrade.

module "agents" {
  source = "../../_shared/node-pool-openstack"

  name_prefix          = "${local.prefix}-agent"
  node_count           = var.agent_count
  flavor_name          = local.agent_flavor
  image_name           = var.image_name
  user_data            = [data.cloudinit_config.node["agent"].rendered]
  network_id           = openstack_networking_network_v2.this.id
  security_group_names = [openstack_networking_secgroup_v2.nodes.name]
  key_pair             = var.ssh_key_pair
  availability_zones   = var.availability_zones
  boot_volume_size_gb  = var.boot_volume_size_gb
  boot_volume_type     = var.boot_volume_type
  metadata             = merge(local.labels, { "rke2-role" = "agent" })
  tags                 = local.tags
  replace_on_change    = true

  depends_on = [module.server_init]
}
