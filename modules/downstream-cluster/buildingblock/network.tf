# Own VPC per downstream cluster, no peering (ADR-015). Nodes sit in private
# subnets without public IPs and reach Rancher (443) and the internet through
# NAT. Rancher never connects into this VPC: RKE2 v2 provisioning hands the
# install script over as EC2 user data, and the agents keep a reverse tunnel
# to Rancher open.
#
# Subnet layout as in rke2-cluster: the VPC CIDR is split into 8 parts
# (newbits 3); private subnets take parts 0-3, public subnets parts 4-7.

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
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.prefix}-vpc" }

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "The AWS credentials belong to account ${data.aws_caller_identity.current.account_id}, but the meshStack tenant is ${var.aws_account_id} (see ADR-013)."
    }
    precondition {
      condition     = length(local.azs) >= 1 && length(local.azs) <= 4
      error_message = "Between 1 and 4 availability zones are needed; the region offers ${length(data.aws_availability_zones.available.names)}."
    }
  }
}

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

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.prefix}-nat" }

  depends_on = [aws_internet_gateway.this]
}

# One NAT gateway (first AZ), as in rke2-cluster. Its IP is the source of all
# node traffic to Rancher: add it to Rancher's ingress allow list if that is
# ever restricted (output nat_public_ip).
resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[local.azs[0]].id
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

# Node security group. Passed to the node driver by name with
# security_group_readonly, so Rancher adds no rules (no SSH, nothing public).
# Inside the cluster all traffic between nodes is allowed: RKE2 needs 6443,
# 9345, 10250, 2379-2381, 8472/udp, 9099 and the NodePort range between nodes,
# and the group contains nothing but this cluster's nodes.
resource "aws_security_group" "nodes" {
  name        = "${local.prefix}-nodes"
  description = "Nodes of downstream cluster ${local.rancher_cluster_name}"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${local.prefix}-nodes" }
}

resource "aws_vpc_security_group_ingress_rule" "nodes_self" {
  security_group_id            = aws_security_group.nodes.id
  description                  = "All traffic between the cluster's nodes"
  referenced_security_group_id = aws_security_group.nodes.id
  ip_protocol                  = "-1"
}

# Egress to Rancher (443 via NAT), registries, the RKE2 installer.
#trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "nodes_all" {
  security_group_id = aws_security_group.nodes.id
  description       = "Egress via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
