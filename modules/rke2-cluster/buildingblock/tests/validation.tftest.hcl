# Input validation rules. Mocked providers: never touches real infrastructure.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    }
  }
  mock_resource "aws_eip" {
    defaults = {
      public_ip = "203.0.113.60"
    }
  }
  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-central-1:123456789012:loadbalancer/net/rke2/0123456789abcdef"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-central-1:123456789012:targetgroup/rke2/0123456789abcdef"
    }
  }
}

mock_provider "http" {}

variables {
  workspace_identifier        = "platform"
  project_identifier          = "rancher-mgmt"
  building_block_uuid         = "3f2b8c1e-1234-4abc-9def-0123456789ab"
  aws_account_id              = "123456789012"
  state_encryption_passphrase = "test-passphrase-not-secret"
  cluster_name                = "mgmt"
  ami_id                      = "ami-0123456789abcdef0"
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

run "rejects_vpc_overlapping_pod_cidr" {
  command = plan
  variables {
    vpc_cidr = "10.42.1.0/24"
  }
  expect_failures = [var.vpc_cidr]
}

run "rejects_vpc_containing_service_cidr" {
  command = plan
  variables {
    vpc_cidr = "10.0.0.0/8"
  }
  expect_failures = [var.vpc_cidr]
}

run "rejects_vpc_too_small" {
  command = plan
  variables {
    vpc_cidr = "192.168.0.0/26"
  }
  expect_failures = [var.vpc_cidr]
}

run "rejects_invalid_vpc_cidr" {
  command = plan
  variables {
    vpc_cidr = "not-a-cidr"
  }
  expect_failures = [var.vpc_cidr]
}

run "accepts_vpc_adjacent_to_pod_cidr" {
  command = plan
  variables {
    vpc_cidr = "10.44.0.0/16"
  }
}

run "accepts_vpc_below_pod_cidr" {
  command = plan
  variables {
    vpc_cidr = "10.41.0.0/16"
  }
}

run "rejects_admin_cert_validity_out_of_range" {
  command = plan
  variables {
    admin_cert_validity_hours = 1
  }
  expect_failures = [var.admin_cert_validity_hours]
}

run "rejects_bad_account_id" {
  command = plan
  variables {
    aws_account_id = "not-an-account"
  }
  expect_failures = [var.aws_account_id]
}

run "rejects_bad_ami_id" {
  command = plan
  variables {
    ami_id = "ubuntu-24.04"
  }
  expect_failures = [var.ami_id]
}

run "rejects_bad_instance_type" {
  command = plan
  variables {
    server_instance_type = "m1.xlarge large"
  }
  expect_failures = [var.server_instance_type]
}

run "rejects_too_many_azs" {
  command = plan
  variables {
    availability_zones = ["a", "b", "c", "d", "e"]
  }
  expect_failures = [var.availability_zones]
}

run "rejects_low_iops" {
  command = plan
  variables {
    root_volume_iops = 100
  }
  expect_failures = [var.root_volume_iops]
}

run "rejects_bad_kms_key" {
  command = plan
  variables {
    kms_key_arn = "alias/my-key"
  }
  expect_failures = [var.kms_key_arn]
}

run "rejects_unknown_ingress_controller" {
  command = plan
  variables {
    ingress_controller = "haproxy"
  }
  expect_failures = [var.ingress_controller]
}

run "rejects_ingress_nginx" {
  command = plan
  variables {
    ingress_controller = "ingress-nginx"
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
