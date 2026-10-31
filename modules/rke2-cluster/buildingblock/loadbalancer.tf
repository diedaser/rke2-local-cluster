# One Octavia LB serves the registration address (9345), the API (6443) and
# ingress (80/443) on a single VIP (ADR-006).

resource "openstack_lb_loadbalancer_v2" "this" {
  name                  = "${local.prefix}-lb"
  vip_subnet_id         = openstack_networking_subnet_v2.this.id
  loadbalancer_provider = var.lb_provider
  tags                  = local.tags

  depends_on = [openstack_networking_router_interface_v2.this]
}

resource "openstack_networking_floatingip_v2" "lb" {
  count = var.assign_floating_ip ? 1 : 0

  pool        = var.external_network_name
  description = "${local.prefix} API and ingress"
  tags        = local.tags
}

resource "openstack_networking_floatingip_associate_v2" "lb" {
  count = var.assign_floating_ip ? 1 : 0

  floating_ip = openstack_networking_floatingip_v2.lb[0].address
  port_id     = openstack_lb_loadbalancer_v2.this.vip_port_id
}

locals {
  server_ips = concat(module.server_init.ips, module.server_join.ips)
  agent_ips  = module.agents.ips

  listeners = {
    api = {
      port          = 6443
      allowed_cidrs = local.api_allowed_cidrs
      members       = local.server_ips
    }
    supervisor = {
      port          = 9345
      allowed_cidrs = [var.subnet_cidr]
      members       = local.server_ips
    }
    http = {
      port          = 80
      allowed_cidrs = local.ingress_allowed_cidrs
      members       = concat(local.server_ips, local.agent_ips)
    }
    https = {
      port          = 443
      allowed_cidrs = local.ingress_allowed_cidrs
      members       = concat(local.server_ips, local.agent_ips)
    }
  }
}

resource "openstack_lb_listener_v2" "this" {
  for_each = local.listeners

  name            = "${local.prefix}-${each.key}"
  loadbalancer_id = openstack_lb_loadbalancer_v2.this.id
  protocol        = "TCP"
  protocol_port   = each.value.port
  allowed_cidrs   = each.value.allowed_cidrs
  tags            = local.tags

  # Long-lived watch connections (kubectl, Rancher agents) must not be cut.
  timeout_client_data = 3600000
  timeout_member_data = 3600000
}

resource "openstack_lb_pool_v2" "this" {
  for_each = local.listeners

  name        = "${local.prefix}-${each.key}"
  listener_id = openstack_lb_listener_v2.this[each.key].id
  protocol    = "TCP"
  lb_method   = "ROUND_ROBIN"
  tags        = local.tags
}

resource "openstack_lb_monitor_v2" "this" {
  for_each = local.listeners

  name        = "${local.prefix}-${each.key}"
  pool_id     = openstack_lb_pool_v2.this[each.key].id
  type        = "TCP"
  delay       = 10
  timeout     = 5
  max_retries = 3
}

resource "openstack_lb_members_v2" "this" {
  for_each = local.listeners

  pool_id = openstack_lb_pool_v2.this[each.key].id

  dynamic "member" {
    for_each = each.value.members
    content {
      address       = member.value
      protocol_port = each.value.port
      subnet_id     = openstack_networking_subnet_v2.this.id
    }
  }
}
