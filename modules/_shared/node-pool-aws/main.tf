# Node pool interface: in → count, instance type, AMI, user_data[], subnets,
# optional instance profile;
# out → ips[], ids[], names[]. Swap this module for another infrastructure
# while keeping the same inputs and outputs.

terraform {
  required_version = ">= 1.8"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73.0"
    }
  }
}

locals {
  instances = var.replace_on_change ? aws_instance.rolling : aws_instance.pinned

  # Index across the whole role (index_offset included), so joining servers
  # continue the AZ round-robin after the first server.
  names = [for i in range(var.node_count) : format("%s-%02d", var.name_prefix, i + var.index_offset)]
}

# Pinned nodes (servers, etcd members). Changes to AMI, user data, subnet,
# key or placement are ignored so OpenTofu never silently replaces an etcd
# member; upgrades follow the manual rolling procedure in docs/operations.md.
resource "aws_instance" "pinned" {
  count = var.replace_on_change ? 0 : var.node_count

  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = element(var.subnet_ids, count.index + var.index_offset)
  vpc_security_group_ids = var.security_group_ids
  placement_group        = var.placement_group
  key_name               = var.key_name
  iam_instance_profile   = var.iam_instance_profile
  user_data_base64       = element(var.user_data_base64, count.index)
  ebs_optimized          = true

  # IMDSv2 only; hop limit 1 keeps pods away from the node's metadata.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    iops                  = var.root_volume_iops
    throughput            = var.root_volume_throughput
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    delete_on_termination = true
    tags                  = merge(var.tags, { Name = local.names[count.index] })
  }

  tags = merge(var.tags, { Name = local.names[count.index] })

  lifecycle {
    ignore_changes = [ami, user_data_base64, subnet_id, key_name, placement_group]
  }
}

# Rolling nodes (agents). A changed AMI or user data replaces the node,
# creating the new one before the old one is destroyed.
resource "aws_instance" "rolling" {
  count = var.replace_on_change ? var.node_count : 0

  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = element(var.subnet_ids, count.index + var.index_offset)
  vpc_security_group_ids      = var.security_group_ids
  placement_group             = var.placement_group
  key_name                    = var.key_name
  iam_instance_profile        = var.iam_instance_profile
  user_data_base64            = element(var.user_data_base64, count.index)
  user_data_replace_on_change = true
  ebs_optimized               = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    iops                  = var.root_volume_iops
    throughput            = var.root_volume_throughput
    encrypted             = true
    kms_key_id            = var.kms_key_arn
    delete_on_termination = true
    tags                  = merge(var.tags, { Name = local.names[count.index] })
  }

  tags = merge(var.tags, { Name = local.names[count.index] })

  lifecycle {
    create_before_destroy = true
  }
}
