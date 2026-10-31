# One-time setup by the platform team. NOT run by meshStack.
#
# Run authenticated as a user (password auth, OS_* environment) scoped to the
# OpenStack project the clusters will live in. The application credential is
# created for that user and inherits the selected roles in that project.

terraform {
  required_version = ">= 1.8"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4.0"
    }
  }
}

data "openstack_identity_auth_scope_v3" "current" {
  name = "current"
}

resource "openstack_identity_application_credential_v3" "meshstack_runner" {
  name         = var.application_credential_name
  description  = "meshStack building block runner for rke2-cluster and rancher. Managed by OpenTofu (backplane)."
  roles        = var.roles
  unrestricted = false
  expires_at   = var.expires_at

  lifecycle {
    precondition {
      condition     = data.openstack_identity_auth_scope_v3.current.project_id == var.project_id
      error_message = "Authenticate scoped to project ${var.project_id} before running the backplane."
    }
  }
}

# Optional quotas. Requires admin rights; disabled by default.
resource "openstack_compute_quotaset_v2" "this" {
  count = var.manage_quotas ? 1 : 0

  project_id    = var.project_id
  instances     = var.quota.instances
  cores         = var.quota.cores
  ram           = var.quota.ram_mb
  server_groups = 10
}

resource "openstack_blockstorage_quotaset_v3" "this" {
  count = var.manage_quotas ? 1 : 0

  project_id = var.project_id
  volumes    = var.quota.volumes
  gigabytes  = var.quota.volume_gb
}

resource "openstack_networking_quota_v2" "this" {
  count = var.manage_quotas ? 1 : 0

  project_id          = var.project_id
  floatingip          = var.quota.floating_ips
  network             = 10
  subnet              = 10
  router              = 5
  security_group      = 20
  security_group_rule = 200
}

resource "openstack_lb_quota_v2" "this" {
  count = var.manage_quotas ? 1 : 0

  project_id     = var.project_id
  loadbalancer   = var.quota.loadbalancers
  listener       = var.quota.loadbalancers * 4
  pool           = var.quota.loadbalancers * 4
  health_monitor = var.quota.loadbalancers * 4
  member         = var.quota.loadbalancers * 4 * 10
}
