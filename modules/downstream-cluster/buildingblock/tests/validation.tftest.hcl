# Input validation rules. Mocked providers: never touches AWS or Rancher.

mock_provider "aws" {
  # All management private subnets live in the management VPC.
  mock_data "aws_subnet" {
    defaults = {
      vpc_id = "vpc-0123456789abcdef0"
    }
  }
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
  mgmt_vpc_id                        = "vpc-0123456789abcdef0"
  mgmt_private_subnet_ids = {
    "eu-central-1c" = "subnet-0000000000000000c"
    "eu-central-1a" = "subnet-0000000000000000a"
    "eu-central-1b" = "subnet-0000000000000000b"
  }
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

run "rejects_foreign_vpc_id" {
  command = plan
  variables {
    mgmt_vpc_id = "10.100.0.0/16"
  }
  expect_failures = [var.mgmt_vpc_id]
}

run "rejects_empty_subnet_map" {
  command = plan
  variables {
    mgmt_private_subnet_ids = {}
  }
  expect_failures = [var.mgmt_private_subnet_ids]
}

run "rejects_non_subnet_ids" {
  command = plan
  variables {
    mgmt_private_subnet_ids = { "eu-central-1a" = "10.100.0.0/19" }
  }
  expect_failures = [var.mgmt_private_subnet_ids]
}
