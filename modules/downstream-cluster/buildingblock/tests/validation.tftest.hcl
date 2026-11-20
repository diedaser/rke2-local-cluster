# Input validation rules. Mocked providers: never touches AWS or Rancher.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_region" {
    defaults = {
      region = "eu-central-1"
    }
  }
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
    }
  }
  mock_data "aws_secretsmanager_secret_version" {
    defaults = {
      secret_string = "{\"url\":\"https://rancher.example.com\",\"username\":\"meshstack-downstream\",\"password\":\"test-password-not-secret\"}"
    }
  }
}

mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code   = 201
      response_body = "{\"token\":\"token-abcde:test-token-not-secret\"}"
    }
  }
}

mock_provider "rancher2" {}

variables {
  workspace_identifier               = "platform"
  project_identifier                 = "apps"
  building_block_uuid                = "5e6f7a8b-1234-4abc-9def-0123456789ab"
  aws_account_id                     = "123456789012"
  state_encryption_passphrase        = "test-passphrase-not-secret"
  downstream_credentials_secret_name = "rancher-9a8b7c6d-rancher-downstream"
  node_driver_access_key_id          = "AKIAEXAMPLEEXAMPLE00"
  node_driver_secret_access_key      = "test-secret-key-not-secret-0123456789012"
  ami_id                             = "ami-0123456789abcdef0"
  cluster_name                       = "apps"
}

run "valid_defaults" {
  command = plan
}

run "rejects_bad_cluster_name" {
  command = plan
  variables {
    cluster_name = "Apps_1"
  }
  expect_failures = [var.cluster_name]
}

run "rejects_even_control_plane_count" {
  command = plan
  variables {
    control_plane_count = "2"
  }
  expect_failures = [var.control_plane_count]
}

run "rejects_zero_workers" {
  command = plan
  variables {
    worker_count = 0
  }
  expect_failures = [var.worker_count]
}

run "rejects_unpinned_kubernetes_version" {
  command = plan
  variables {
    kubernetes_version = "stable"
  }
  expect_failures = [var.kubernetes_version]
}

run "rejects_foreign_secret_name" {
  command = plan
  variables {
    downstream_credentials_secret_name = "rancher-9a8b7c6d-rancher-admin"
  }
  expect_failures = [var.downstream_credentials_secret_name]
}

run "rejects_bad_access_key_id" {
  command = plan
  variables {
    node_driver_access_key_id = "not-a-key"
  }
  expect_failures = [var.node_driver_access_key_id]
}

run "rejects_bad_secret_access_key" {
  command = plan
  variables {
    node_driver_secret_access_key = "too-short"
  }
  expect_failures = [var.node_driver_secret_access_key]
}

run "rejects_vpc_cidr_in_pod_range" {
  command = plan
  variables {
    vpc_cidr = "10.42.128.0/24"
  }
  expect_failures = [var.vpc_cidr]
}

run "rejects_vpc_cidr_covering_service_range" {
  command = plan
  variables {
    vpc_cidr = "10.43.0.0/16"
  }
  expect_failures = [var.vpc_cidr]
}

run "rejects_too_large_vpc" {
  command = plan
  variables {
    vpc_cidr = "10.0.0.0/8"
  }
  expect_failures = [var.vpc_cidr]
}

run "rejects_too_many_azs" {
  command = plan
  variables {
    availability_zones = ["eu-central-1a", "eu-central-1b", "eu-central-1c", "eu-central-1d", "eu-central-1e"]
  }
  expect_failures = [var.availability_zones]
}

run "rejects_bad_ami" {
  command = plan
  variables {
    ami_id = "ubuntu-24.04"
  }
  expect_failures = [var.ami_id]
}

run "rejects_bad_kms_key" {
  command = plan
  variables {
    kms_key_arn = "alias/my-key"
  }
  expect_failures = [var.kms_key_arn]
}

run "rejects_small_root_volume" {
  command = plan
  variables {
    root_volume_size_gb = 20
  }
  expect_failures = [var.root_volume_size_gb]
}

run "rejects_bad_instance_type" {
  command = plan
  variables {
    worker_instance_type = "large"
  }
  expect_failures = [var.worker_instance_type]
}
