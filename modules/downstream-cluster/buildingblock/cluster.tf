# Downstream RKE2 cluster provisioned by Rancher with the Amazon EC2 node
# driver (ADR-015). Rancher owns the instances; OpenTofu owns the cluster
# object, the machine configs and the cloud credential.

locals {
  roles = {
    control-plane = { count = tonumber(var.control_plane_count), instance_type = var.control_plane_instance_type }
    worker        = { count = var.worker_count, instance_type = var.worker_instance_type }
  }

  # A machine config pins one subnet and zone, so every role gets one pool
  # per AZ. Counts are spread round-robin: 3 control-plane nodes over 3 AZs
  # = 1 per AZ, 5 = 2+2+1. Pools that would be empty are not created.
  pools = merge([
    for role, cfg in local.roles : {
      for i, az in local.azs : "${role}-${az}" => {
        role          = role
        az            = az
        quantity      = floor(cfg.count / length(local.azs)) + (i < cfg.count % length(local.azs) ? 1 : 0)
        instance_type = cfg.instance_type
      } if floor(cfg.count / length(local.azs)) + (i < cfg.count % length(local.azs) ? 1 : 0) > 0
    }
  ]...)

  # The driver takes tags as "k1,v1,k2,v2" and the zone as its letter only.
  machine_tags = join(",", flatten([for k, v in local.labels : [k, v]]))
}

resource "rancher2_cloud_credential" "this" {
  name        = local.prefix
  description = "EC2 node driver for downstream cluster ${local.rancher_cluster_name} (meshStack building block ${var.building_block_uuid})."

  amazonec2_credential_config {
    access_key     = var.node_driver_access_key_id
    secret_key     = var.node_driver_secret_access_key
    default_region = local.region
  }
}

resource "rancher2_machine_config_v2" "pool" {
  for_each = local.pools

  generate_name = "${local.prefix}-${each.key}"

  amazonec2_config {
    ami                     = var.ami_id
    region                  = local.region
    vpc_id                  = var.mgmt_vpc_id
    subnet_id               = data.aws_subnet.node[each.value.az].id
    zone                    = substr(each.value.az, length(each.value.az) - 1, 1)
    instance_type           = each.value.instance_type
    security_group          = [aws_security_group.nodes.name]
    security_group_readonly = true
    private_address_only    = true
    use_private_address     = true
    root_size               = tostring(var.root_volume_size_gb)
    volume_type             = "gp3"
    encrypt_ebs_volume      = true
    kms_key                 = var.kms_key_arn
    http_endpoint           = "enabled"
    http_tokens             = "required"
    tags                    = local.machine_tags
  }
}

resource "rancher2_cluster_v2" "this" {
  name               = local.rancher_cluster_name
  kubernetes_version = var.kubernetes_version
  labels             = local.labels

  # Default for all pools; meshstack-downstream owns it (it created it).
  cloud_credential_secret_name = rancher2_cloud_credential.this.id

  rke_config {
    dynamic "machine_pools" {
      for_each = local.pools
      content {
        name               = machine_pools.key
        control_plane_role = machine_pools.value.role == "control-plane"
        etcd_role          = machine_pools.value.role == "control-plane"
        worker_role        = machine_pools.value.role == "worker"
        quantity           = machine_pools.value.quantity

        machine_config {
          kind = rancher2_machine_config_v2.pool[machine_pools.key].kind
          name = rancher2_machine_config_v2.pool[machine_pools.key].name
        }
      }
    }

    # Explicit like the management cluster (ADR-008): the defaults change
    # across RKE2 releases.
    machine_global_config = yamlencode({
      cni                = "canal"
      ingress-controller = "traefik"
    })
  }

  # With machine pools, create (and update) waits until the cluster's
  # "Updated" condition is true and fails early on a stuck False condition
  # (provider v15, ADR-007). Delete waits until Rancher removed the cluster,
  # i.e. after its finalizers deleted the machines.
  timeouts {
    create = "45m"
    update = "45m"
    delete = "45m"
  }

  # Rules exist before the first node boots and outlive the last one.
  depends_on = [
    aws_vpc_security_group_ingress_rule.nodes_self,
    aws_vpc_security_group_egress_rule.nodes_all,
  ]
}
