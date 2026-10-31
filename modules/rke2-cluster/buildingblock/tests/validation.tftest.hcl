# Input validation rules. Mocked providers: never touches real infrastructure.

mock_provider "openstack" {
  mock_data "openstack_identity_auth_scope_v3" {
    defaults = {
      project_id = "0123456789abcdef0123456789abcdef"
    }
  }
}

mock_provider "http" {}

variables {
  workspace_identifier        = "platform"
  project_identifier          = "rancher-mgmt"
  building_block_uuid         = "3f2b8c1e-1234-4abc-9def-0123456789ab"
  openstack_project_id        = "0123456789abcdef0123456789abcdef"
  state_encryption_passphrase = "test-passphrase-not-secret"
  cluster_name                = "mgmt"
  server_flavor               = "m1.xlarge"
  image_name                  = "ubuntu-24.04"
  external_network_name       = "public"
  api_allowed_cidrs           = ["10.0.0.0/8"]
}

run "valid_defaults" {
  command = plan
}

run "rejects_bad_cluster_name" {
  command = plan
  variables {
    cluster_name = "Mgmt_Cluster"
  }
  expect_failures = [var.cluster_name]
}

run "rejects_too_short_cluster_name" {
  command = plan
  variables {
    cluster_name = "ab"
  }
  expect_failures = [var.cluster_name]
}

run "rejects_even_server_count" {
  command = plan
  variables {
    server_count = "2"
  }
  expect_failures = [var.server_count]
}

run "accepts_numeric_server_count" {
  command = plan
  variables {
    server_count = 5
  }
}

run "rejects_negative_agent_count" {
  command = plan
  variables {
    agent_count = -1
  }
  expect_failures = [var.agent_count]
}

run "rejects_fractional_agent_count" {
  command = plan
  variables {
    agent_count = 1.5
  }
  expect_failures = [var.agent_count]
}

run "rejects_unpinned_rke2_version" {
  command = plan
  variables {
    rke2_version = "latest"
  }
  expect_failures = [var.rke2_version]
}

run "rejects_unknown_hardening_profile" {
  command = plan
  variables {
    hardening_profile = "cis-1.23"
  }
  expect_failures = [var.hardening_profile]
}

run "rejects_invalid_api_cidr" {
  command = plan
  variables {
    api_allowed_cidrs = ["10.0.0.0/33"]
  }
  expect_failures = [var.api_allowed_cidrs]
}

run "rejects_invalid_runner_cidr" {
  command = plan
  variables {
    runner_egress_cidrs = ["not-a-cidr"]
  }
  expect_failures = [var.runner_egress_cidrs]
}

run "rejects_short_passphrase" {
  command = plan
  variables {
    state_encryption_passphrase = "short"
  }
  expect_failures = [var.state_encryption_passphrase]
}

run "rejects_subnet_overlapping_pod_cidr" {
  command = plan
  variables {
    subnet_cidr = "10.42.1.0/24"
  }
  expect_failures = [var.subnet_cidr]
}

run "rejects_admin_cert_validity_out_of_range" {
  command = plan
  variables {
    admin_cert_validity_hours = 1
  }
  expect_failures = [var.admin_cert_validity_hours]
}

run "rejects_bad_project_id" {
  command = plan
  variables {
    openstack_project_id = "not-a-project"
  }
  expect_failures = [var.openstack_project_id]
}

run "rejects_unknown_ingress_controller" {
  command = plan
  variables {
    ingress_controller = "haproxy"
  }
  expect_failures = [var.ingress_controller]
}

run "rejects_plain_http_install_script" {
  command = plan
  variables {
    rke2_install_script_url = "http://get.rke2.io"
  }
  expect_failures = [var.rke2_install_script_url]
}

run "rejects_bad_snapshot_cron" {
  command = plan
  variables {
    etcd_snapshot_schedule_cron = "hourly"
  }
  expect_failures = [var.etcd_snapshot_schedule_cron]
}
