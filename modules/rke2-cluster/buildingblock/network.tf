data "openstack_networking_network_v2" "external" {
  name     = var.external_network_name
  external = true
}

resource "openstack_networking_network_v2" "this" {
  name           = "${local.prefix}-net"
  admin_state_up = true
  tags           = local.tags

  lifecycle {
    precondition {
      condition     = data.openstack_identity_auth_scope_v3.current.project_id == var.openstack_project_id
      error_message = "The OpenStack credentials are scoped to project ${data.openstack_identity_auth_scope_v3.current.project_id}, but the meshStack tenant is ${var.openstack_project_id}. Use credentials for the tenant's project (see ADR-013)."
    }
  }
}

resource "openstack_networking_subnet_v2" "this" {
  name            = "${local.prefix}-subnet"
  network_id      = openstack_networking_network_v2.this.id
  cidr            = var.subnet_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers
  tags            = local.tags
}

resource "openstack_networking_router_v2" "this" {
  name                = "${local.prefix}-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external.id
  tags                = local.tags
}

resource "openstack_networking_router_interface_v2" "this" {
  router_id = openstack_networking_router_v2.this.id
  subnet_id = openstack_networking_subnet_v2.this.id
}

# --- Security groups (CONTRIBUTING.md, network requirements) -----------------------------------
# The subnet CIDR is the source for LB-facing ports, because Octavia amphorae
# connect to members from addresses inside the member subnet.

resource "openstack_networking_secgroup_v2" "nodes" {
  name        = "${local.prefix}-nodes"
  description = "RKE2 nodes (servers and agents) of ${var.cluster_name}"
  tags        = local.tags
}

resource "openstack_networking_secgroup_v2" "servers" {
  name        = "${local.prefix}-servers"
  description = "RKE2 server nodes (etcd) of ${var.cluster_name}"
  tags        = local.tags
}

locals {
  node_rules = {
    api        = { protocol = "tcp", min = 6443, max = 6443, cidr = var.subnet_cidr, group = null, description = "Kubernetes API from LB and nodes" }
    supervisor = { protocol = "tcp", min = 9345, max = 9345, cidr = var.subnet_cidr, group = null, description = "RKE2 supervisor from LB and nodes" }
    http       = { protocol = "tcp", min = 80, max = 80, cidr = var.subnet_cidr, group = null, description = "Ingress HTTP from LB" }
    https      = { protocol = "tcp", min = 443, max = 443, cidr = var.subnet_cidr, group = null, description = "Ingress HTTPS from LB" }
    kubelet    = { protocol = "tcp", min = 10250, max = 10250, cidr = null, group = "nodes", description = "kubelet" }
    vxlan      = { protocol = "udp", min = 8472, max = 8472, cidr = null, group = "nodes", description = "Canal/Flannel VXLAN" }
    canal      = { protocol = "tcp", min = 9099, max = 9099, cidr = null, group = "nodes", description = "Canal health checks" }
    nodeports  = { protocol = "tcp", min = 30000, max = 32767, cidr = null, group = "nodes", description = "NodePorts (TCP)" }
    nodeportsu = { protocol = "udp", min = 30000, max = 32767, cidr = null, group = "nodes", description = "NodePorts (UDP)" }
    icmp       = { protocol = "icmp", min = null, max = null, cidr = null, group = "nodes", description = "ICMP between nodes" }
  }
}

resource "openstack_networking_secgroup_rule_v2" "nodes" {
  for_each = local.node_rules

  security_group_id = openstack_networking_secgroup_v2.nodes.id
  description       = each.value.description
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.min
  port_range_max    = each.value.max
  remote_ip_prefix  = each.value.cidr
  remote_group_id   = each.value.group == "nodes" ? openstack_networking_secgroup_v2.nodes.id : null
}

resource "openstack_networking_secgroup_rule_v2" "etcd" {
  security_group_id = openstack_networking_secgroup_v2.servers.id
  description       = "etcd client, peer, metrics between servers"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 2379
  port_range_max    = 2381
  remote_group_id   = openstack_networking_secgroup_v2.servers.id
}

# Octavia providers that preserve the client address (for example OVN) forward
# client traffic without SNAT, so the client allow lists must also be open on
# the nodes. Nodes have no public addresses; the LB listener allow lists stay
# the first filter.
locals {
  client_rules = merge(
    { for c in local.api_allowed_cidrs : "api-${c}" => { port = 6443, cidr = c } },
    { for c in local.ingress_allowed_cidrs : "http-${c}" => { port = 80, cidr = c } },
    { for c in local.ingress_allowed_cidrs : "https-${c}" => { port = 443, cidr = c } },
  )
}

resource "openstack_networking_secgroup_rule_v2" "clients" {
  for_each = { for k, v in local.client_rules : k => v if v.cidr != var.subnet_cidr }

  security_group_id = openstack_networking_secgroup_v2.nodes.id
  description       = "Client traffic via LB without SNAT (port ${each.value.port})"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = each.value.cidr
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  for_each = toset(var.ssh_allowed_cidrs)

  security_group_id = openstack_networking_secgroup_v2.nodes.id
  description       = "Break-glass SSH (never used by OpenTofu)"
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = each.value
}
