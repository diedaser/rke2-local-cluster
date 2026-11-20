# Network Load Balancers (ADR-006).
#
# internal: always present, in the private subnets. Serves the registration
#   address (9345) and the API (6443) to the nodes. Without a public NLB it
#   also serves clients on 6443/80/443.
# public:   optional (public_load_balancer), in the public subnets. Serves
#   clients on 6443/80/443. 9345 is never public.
#
# Target groups do not preserve client IPs: RKE2 nodes reach the NLB that
# targets themselves (registration, hairpin to the Rancher hostname), which
# fails with client IP preservation.

locals {
  load_balancers = toset(concat(["internal"], var.public_load_balancer ? ["public"] : []))

  client_lb = var.public_load_balancer ? "public" : "internal"

  server_ids = concat(module.server_init.ids, module.server_join.ids)
  agent_ids  = module.agents.ids
  node_count = local.server_count + var.agent_count

  # Allow lists per listener. The internal API and supervisor listeners admit
  # the management nodes by security group (lb_internal_from_nodes), not the
  # VPC CIDR: downstream clusters share this VPC (ADR-015) and must not reach
  # the management API or the node-join endpoint. Without a public NLB, the
  # API listener also admits the API client CIDRs.
  listeners = merge(
    {
      "int-api" = { lb = "internal", port = 6443, servers_only = true, cidrs = var.public_load_balancer ? [] : local.api_client_cidrs }
      "int-sup" = { lb = "internal", port = 9345, servers_only = true, cidrs = [] }
    },
    {
      for name, port in { api = 6443, http = 80, https = 443 } :
      "${substr(local.client_lb, 0, 3)}-${name}" => {
        lb           = local.client_lb
        port         = port
        servers_only = name == "api"
        cidrs = distinct(concat(
          var.public_load_balancer ? [] : [var.vpc_cidr],
          name == "api" ? local.api_client_cidrs : local.ingress_client_cidrs,
        ))
      } if !(local.client_lb == "internal" && name == "api")
    },
  )

  # One attachment per listener and node. Keys use indexes so they are known
  # at plan time.
  attachments = merge([
    for l, cfg in local.listeners : {
      for i in range(cfg.servers_only ? local.server_count : local.node_count) :
      "${l}-${i}" => { listener = l, index = i, port = cfg.port }
    }
  ]...)

  lb_ingress_rules = merge([
    for l, cfg in local.listeners : {
      for c in cfg.cidrs : "${l}-${c}" => { lb = cfg.lb, port = cfg.port, cidr = c }
    }
  ]...)
}

resource "aws_security_group" "lb" {
  for_each = local.load_balancers

  name        = "${local.prefix}-lb-${each.key}"
  description = "${each.key} NLB of ${var.cluster_name}"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${local.prefix}-lb-${each.key}" }
}

# Public ingress is the purpose of the public NLB; ingress_allowed_cidrs
# defaults to 0.0.0.0/0 for the Rancher UI.
#trivy:ignore:AVD-AWS-0107
resource "aws_vpc_security_group_ingress_rule" "lb_clients" {
  for_each = local.lb_ingress_rules

  security_group_id = aws_security_group.lb[each.value.lb].id
  description       = "Port ${each.value.port} from ${each.value.cidr}"
  cidr_ipv4         = each.value.cidr
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
}

# Nodes reach the API and register through the internal NLB. Source is the
# node security group (target groups do not preserve client IPs, so the NLB
# sees the node's own ENI, also for hairpin traffic).
resource "aws_vpc_security_group_ingress_rule" "lb_internal_from_nodes" {
  for_each = { api = 6443, supervisor = 9345 }

  security_group_id            = aws_security_group.lb["internal"].id
  description                  = "Port ${each.value} from the management nodes"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
}

# Pods reach the public hostname (Rancher URL) through NAT. Keep that path
# open even when the client allow lists are restricted.
resource "aws_vpc_security_group_ingress_rule" "lb_public_from_nat" {
  for_each = var.public_load_balancer ? { api = 6443, http = 80, https = 443 } : {}

  security_group_id = aws_security_group.lb["public"].id
  description       = "Port ${each.value} from the cluster NAT gateway"
  cidr_ipv4         = "${aws_eip.nat.public_ip}/32"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
}

resource "aws_vpc_security_group_egress_rule" "lb_to_vpc" {
  for_each = local.load_balancers

  security_group_id = aws_security_group.lb[each.key].id
  description       = "Forwarding and health checks to the nodes"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
}

resource "aws_lb" "internal" {
  name                             = "rke2-${local.short_id}-internal"
  load_balancer_type               = "network"
  internal                         = true
  subnets                          = local.private_subnet_ids
  security_groups                  = [aws_security_group.lb["internal"].id]
  enable_cross_zone_load_balancing = true

  tags = { Name = "${local.prefix}-internal" }
}

#trivy:ignore:AVD-AWS-0053
resource "aws_lb" "public" {
  count = var.public_load_balancer ? 1 : 0

  name                             = "rke2-${local.short_id}-public"
  load_balancer_type               = "network"
  internal                         = false
  subnets                          = local.public_subnet_ids
  security_groups                  = [aws_security_group.lb["public"].id]
  enable_cross_zone_load_balancing = true

  tags = { Name = "${local.prefix}-public" }

  depends_on = [aws_route.public_internet]
}

locals {
  lb_arns = merge(
    { internal = aws_lb.internal.arn },
    var.public_load_balancer ? { public = aws_lb.public[0].arn } : {},
  )
}

resource "aws_lb_target_group" "this" {
  for_each = local.listeners

  name                 = "rke2-${local.short_id}-${each.key}"
  vpc_id               = aws_vpc.this.id
  protocol             = "TCP"
  port                 = each.value.port
  target_type          = "instance"
  preserve_client_ip   = false
  deregistration_delay = 30

  health_check {
    protocol            = "TCP"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "${local.prefix}-${each.key}" }
}

resource "aws_lb_listener" "this" {
  for_each = local.listeners

  load_balancer_arn = local.lb_arns[each.value.lb]
  protocol          = "TCP"
  port              = each.value.port

  # Long-lived watch connections (kubectl, Rancher agents) must not be cut.
  tcp_idle_timeout_seconds = 3600

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }
}

resource "aws_lb_target_group_attachment" "this" {
  for_each = local.attachments

  target_group_arn = aws_lb_target_group.this[each.value.listener].arn
  target_id        = concat(local.server_ids, local.agent_ids)[each.value.index]
  port             = each.value.port
}
