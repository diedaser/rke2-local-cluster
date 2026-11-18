# Dedicated VPC per cluster: one private subnet per AZ for the nodes, one public
# subnet per AZ for the NAT gateway and the public NLB. Nodes have no public
# addresses; they reach the internet (get.rke2.io, registries) through NAT.
#
# Subnet layout: the VPC CIDR is split into 8 equal parts (newbits 3). Private
# subnets take parts 0-3, public subnets parts 4-7, so at most 4 AZs.

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(
    sort(data.aws_availability_zones.available.names), 0, min(3, length(data.aws_availability_zones.available.names))
  )

  private_subnet_ids = [for az in local.azs : aws_subnet.private[az].id]
  public_subnet_ids  = [for az in local.azs : aws_subnet.public[az].id]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.prefix}-vpc" }

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "The AWS credentials belong to account ${data.aws_caller_identity.current.account_id}, but the meshStack tenant is ${var.aws_account_id}. Use credentials for the tenant's account (see ADR-013)."
    }
    precondition {
      condition     = length(local.azs) >= 1 && length(local.azs) <= 4
      error_message = "Between 1 and 4 availability zones are needed; the region offers ${length(data.aws_availability_zones.available.names)}."
    }
  }
}

# Strip all rules from the VPC default security group; nothing uses it.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.prefix}-default-deny" }
}

resource "aws_subnet" "private" {
  for_each = { for i, az in local.azs : az => i }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 3, each.value)

  tags = { Name = "${local.prefix}-private-${each.key}" }
}

resource "aws_subnet" "public" {
  for_each = { for i, az in local.azs : az => i }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, 3, each.value + 4)

  tags = { Name = "${local.prefix}-public-${each.key}" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.prefix}-igw" }
}

# One NAT gateway (first AZ). Losing that AZ cuts node egress but not
# in-cluster traffic or the NLB path; see docs/operations.md.
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.prefix}-nat" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = local.public_subnet_ids[0]
  tags          = { Name = "${local.prefix}-nat" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.prefix}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.prefix}-private" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# --- Security groups (CONTRIBUTING.md, network requirements) -------------------
# Target groups do not preserve client IPs (loadbalancer.tf), so node-facing
# LB traffic always comes from the LB security groups. Client allow lists are
# enforced on the LB security groups only.

resource "aws_security_group" "nodes" {
  name        = "${local.prefix}-nodes"
  description = "RKE2 nodes (servers and agents) of ${var.cluster_name}"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${local.prefix}-nodes" }
}

resource "aws_security_group" "servers" {
  name        = "${local.prefix}-servers"
  description = "RKE2 server nodes (etcd) of ${var.cluster_name}"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${local.prefix}-servers" }
}

locals {
  # Node to node. Agents talk to servers on 6443/9345 directly once joined.
  node_self_rules = {
    api        = { protocol = "tcp", from = 6443, to = 6443, description = "Kubernetes API between nodes" }
    supervisor = { protocol = "tcp", from = 9345, to = 9345, description = "RKE2 supervisor between nodes" }
    kubelet    = { protocol = "tcp", from = 10250, to = 10250, description = "kubelet" }
    vxlan      = { protocol = "udp", from = 8472, to = 8472, description = "Canal/Flannel VXLAN" }
    canal      = { protocol = "tcp", from = 9099, to = 9099, description = "Canal health checks" }
    nodeports  = { protocol = "tcp", from = 30000, to = 32767, description = "NodePorts (TCP)" }
    nodeportsu = { protocol = "udp", from = 30000, to = 32767, description = "NodePorts (UDP)" }
    icmp       = { protocol = "icmp", from = -1, to = -1, description = "ICMP between nodes" }
  }

  # LB to node, one rule per listener. Health checks use the same ports.
  node_lb_rules = { for l, cfg in local.listeners : l => { lb = cfg.lb, port = cfg.port } }
}

resource "aws_vpc_security_group_ingress_rule" "nodes_self" {
  for_each = local.node_self_rules

  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.nodes.id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from
  to_port                      = each.value.to
}

resource "aws_vpc_security_group_ingress_rule" "nodes_from_lb" {
  for_each = local.node_lb_rules

  security_group_id            = aws_security_group.nodes.id
  referenced_security_group_id = aws_security_group.lb[each.value.lb].id
  description                  = "Port ${each.value.port} from the ${each.value.lb} NLB"
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
}

resource "aws_vpc_security_group_ingress_rule" "etcd" {
  security_group_id            = aws_security_group.servers.id
  referenced_security_group_id = aws_security_group.servers.id
  description                  = "etcd client, peer, metrics between servers"
  ip_protocol                  = "tcp"
  from_port                    = 2379
  to_port                      = 2381
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_allowed_cidrs)

  security_group_id = aws_security_group.nodes.id
  description       = "Break-glass SSH (never used by OpenTofu)"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

# Nodes pull the RKE2 installer, images and charts from the internet.
#trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "nodes_all" {
  security_group_id = aws_security_group.nodes.id
  description       = "All egress (installer, registries, Helm repos via NAT)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
