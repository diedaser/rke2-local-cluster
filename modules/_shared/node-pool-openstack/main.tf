# Node pool interface: in → count, flavor, image, user_data[]; out → ips[].
# Swap this module for another infrastructure (vSphere, Hetzner, AWS) while
# keeping the same inputs and outputs.

terraform {
  required_version = ">= 1.8"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4.0"
    }
  }
}

locals {
  instances = var.replace_on_change ? openstack_compute_instance_v2.rolling : openstack_compute_instance_v2.pinned
}

# Pinned nodes (servers, etcd members). Changes to image or user_data are
# ignored so OpenTofu never silently replaces an etcd member; upgrades follow
# the manual rolling procedure in docs/operations.md.
resource "openstack_compute_instance_v2" "pinned" {
  count = var.replace_on_change ? 0 : var.node_count

  name              = format("%s-%02d", var.name_prefix, count.index + var.index_offset)
  flavor_name       = var.flavor_name
  key_pair          = var.key_pair
  security_groups   = var.security_group_names
  user_data         = element(var.user_data, count.index)
  availability_zone = length(var.availability_zones) > 0 ? element(var.availability_zones, count.index) : null
  metadata          = var.metadata
  tags              = var.tags
  config_drive      = true

  block_device {
    uuid                  = data.openstack_images_image_v2.this.id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = var.boot_volume_size_gb
    volume_type           = var.boot_volume_type
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    uuid = var.network_id
  }

  dynamic "scheduler_hints" {
    for_each = var.server_group_id == null ? [] : [var.server_group_id]
    content {
      group = scheduler_hints.value
    }
  }

  lifecycle {
    ignore_changes = [user_data, image_id, image_name, block_device, key_pair, availability_zone]
  }
}

# Rolling nodes (agents). A changed image or user_data replaces the node,
# creating the new one before the old one is destroyed.
resource "openstack_compute_instance_v2" "rolling" {
  count = var.replace_on_change ? var.node_count : 0

  name              = format("%s-%02d", var.name_prefix, count.index + var.index_offset)
  flavor_name       = var.flavor_name
  key_pair          = var.key_pair
  security_groups   = var.security_group_names
  user_data         = element(var.user_data, count.index)
  availability_zone = length(var.availability_zones) > 0 ? element(var.availability_zones, count.index) : null
  metadata          = var.metadata
  tags              = var.tags
  config_drive      = true

  block_device {
    uuid                  = data.openstack_images_image_v2.this.id
    source_type           = "image"
    destination_type      = "volume"
    volume_size           = var.boot_volume_size_gb
    volume_type           = var.boot_volume_type
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    uuid = var.network_id
  }

  dynamic "scheduler_hints" {
    for_each = var.server_group_id == null ? [] : [var.server_group_id]
    content {
      group = scheduler_hints.value
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "openstack_images_image_v2" "this" {
  name        = var.image_name
  most_recent = true
}
