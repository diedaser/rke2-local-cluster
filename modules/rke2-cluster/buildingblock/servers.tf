# Server nodes: control plane + etcd (ADR-006).
#
# The first server initialises the cluster; the others join through the LB
# VIP on 9345. Server instances ignore image/user_data changes (see
# _shared/node-pool-openstack) so OpenTofu never silently replaces an etcd
# member. RKE2 upgrades on servers follow docs/operations.md.
#
# CAUTION (CONTRIBUTING.md rule 8): any plan destroying
# module.server_init.openstack_compute_instance_v2.pinned[0] or
# module.server_join.openstack_compute_instance_v2.pinned[*] removes etcd
# members. Call it out in review.

resource "openstack_compute_servergroup_v2" "servers" {
  name     = "${local.prefix}-servers"
  policies = ["soft-anti-affinity"]
}

module "server_init" {
  source = "../../_shared/node-pool-openstack"

  name_prefix          = "${local.prefix}-server"
  node_count           = 1
  flavor_name          = var.server_flavor
  image_name           = var.image_name
  user_data            = [data.cloudinit_config.node["server_init"].rendered]
  network_id           = openstack_networking_network_v2.this.id
  security_group_names = [openstack_networking_secgroup_v2.nodes.name, openstack_networking_secgroup_v2.servers.name]
  server_group_id      = openstack_compute_servergroup_v2.servers.id
  key_pair             = var.ssh_key_pair
  availability_zones   = var.availability_zones
  boot_volume_size_gb  = var.boot_volume_size_gb
  boot_volume_type     = var.boot_volume_type
  metadata             = merge(local.labels, { "rke2-role" = "server" })
  tags                 = local.tags
  replace_on_change    = false

  depends_on = [
    openstack_networking_router_interface_v2.this,
    openstack_networking_secgroup_rule_v2.nodes,
    openstack_networking_secgroup_rule_v2.etcd,
  ]
}

module "server_join" {
  source = "../../_shared/node-pool-openstack"

  name_prefix          = "${local.prefix}-server"
  index_offset         = 1
  node_count           = local.join_server_count
  flavor_name          = var.server_flavor
  image_name           = var.image_name
  user_data            = [data.cloudinit_config.node["server_join"].rendered]
  network_id           = openstack_networking_network_v2.this.id
  security_group_names = [openstack_networking_secgroup_v2.nodes.name, openstack_networking_secgroup_v2.servers.name]
  server_group_id      = openstack_compute_servergroup_v2.servers.id
  key_pair             = var.ssh_key_pair
  availability_zones   = length(var.availability_zones) > 0 ? concat(slice(var.availability_zones, 1, length(var.availability_zones)), [var.availability_zones[0]]) : []
  boot_volume_size_gb  = var.boot_volume_size_gb
  boot_volume_type     = var.boot_volume_type
  metadata             = merge(local.labels, { "rke2-role" = "server" })
  tags                 = local.tags
  replace_on_change    = false

  depends_on = [module.server_init]
}
