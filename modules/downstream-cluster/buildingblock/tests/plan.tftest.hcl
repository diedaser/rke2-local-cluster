# Resources, pool layout and Rancher login, with mocked providers.
# Never touches AWS or Rancher.

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
      names = ["eu-central-1c", "eu-central-1a", "eu-central-1b"]
    }
  }
  mock_data "aws_secretsmanager_secret_version" {
    defaults = {
      # Test-only login, no real credentials.
      secret_string = "{\"url\":\"https://rancher.example.com/\",\"username\":\"meshstack-downstream\",\"password\":\"test-password-not-secret\"}"
    }
  }
  mock_resource "aws_eip" {
    defaults = {
      public_ip = "203.0.113.70"
    }
  }
}

mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code   = 201
      response_body = "{\"type\":\"token\",\"token\":\"token-abcde:test-token-not-secret\"}"
    }
  }
}

mock_provider "rancher2" {
  mock_resource "rancher2_cluster_v2" {
    defaults = {
      cluster_v1_id = "c-m-abcd1234"
    }
  }
  mock_resource "rancher2_machine_config_v2" {
    defaults = {
      kind = "Amazonec2Config"
    }
  }
  mock_resource "rancher2_cloud_credential" {
    defaults = {
      id = "cattle-global-data:cc-abcde"
    }
  }
}

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

run "default_cluster" {
  command = apply

  assert {
    condition     = rancher2_cluster_v2.this.name == "apps-5e6f7a8b"
    error_message = "The Rancher cluster name must be <cluster_name>-<short building block id>."
  }

  assert {
    condition = local.pools == {
      "control-plane-eu-central-1a" = { role = "control-plane", az = "eu-central-1a", quantity = 1, instance_type = "m7i.xlarge" }
      "control-plane-eu-central-1b" = { role = "control-plane", az = "eu-central-1b", quantity = 1, instance_type = "m7i.xlarge" }
      "control-plane-eu-central-1c" = { role = "control-plane", az = "eu-central-1c", quantity = 1, instance_type = "m7i.xlarge" }
      "worker-eu-central-1a"        = { role = "worker", az = "eu-central-1a", quantity = 1, instance_type = "m7i.large" }
      "worker-eu-central-1b"        = { role = "worker", az = "eu-central-1b", quantity = 1, instance_type = "m7i.large" }
    }
    error_message = "3 control-plane and 2 worker nodes must be spread one per AZ, empty pools omitted."
  }

  assert {
    condition = alltrue([for k, p in rancher2_cluster_v2.this.rke_config[0].machine_pools : (
      p.control_plane_role == startswith(p.name, "control-plane") &&
      p.etcd_role == startswith(p.name, "control-plane") &&
      p.worker_role == startswith(p.name, "worker")
    )])
    error_message = "Control-plane pools carry etcd + control plane, worker pools only the worker role."
  }

  assert {
    condition = alltrue([for k, m in rancher2_machine_config_v2.pool : (
      m.amazonec2_config[0].private_address_only &&
      m.amazonec2_config[0].use_private_address &&
      m.amazonec2_config[0].security_group_readonly &&
      tolist(m.amazonec2_config[0].security_group) == tolist(["apps-5e6f7a8b-nodes"]) &&
      m.amazonec2_config[0].http_tokens == "required" &&
      m.amazonec2_config[0].volume_type == "gp3" &&
      m.amazonec2_config[0].encrypt_ebs_volume &&
      m.amazonec2_config[0].root_size == "100" &&
      m.amazonec2_config[0].region == "eu-central-1"
    )])
    error_message = "Nodes must be private-only, IMDSv2, encrypted gp3, in the module's read-only security group."
  }

  assert {
    condition = (
      rancher2_machine_config_v2.pool["control-plane-eu-central-1c"].amazonec2_config[0].zone == "c" &&
      rancher2_machine_config_v2.pool["control-plane-eu-central-1c"].amazonec2_config[0].subnet_id == aws_subnet.private["eu-central-1c"].id
    )
    error_message = "Each pool must use the zone letter and the private subnet of its AZ."
  }

  assert {
    condition     = strcontains(rancher2_machine_config_v2.pool["worker-eu-central-1a"].amazonec2_config[0].tags, "building-block,downstream-cluster")
    error_message = "Instances must carry the meshStack labels as driver tags (k1,v1,... format)."
  }

  assert {
    condition = (
      rancher2_cloud_credential.this.amazonec2_credential_config[0].default_region == "eu-central-1" &&
      rancher2_cluster_v2.this.cloud_credential_secret_name == "cattle-global-data:cc-abcde"
    )
    error_message = "The cluster must use the module's node-driver cloud credential."
  }

  assert {
    condition     = yamldecode(rancher2_cluster_v2.this.rke_config[0].machine_global_config) == { cni = "canal", "ingress-controller" = "traefik" }
    error_message = "CNI and ingress controller must be set explicitly (ADR-008)."
  }

  assert {
    condition = (
      data.http.rancher_login.method == "POST" &&
      data.http.rancher_login.url == "https://rancher.example.com/v3-public/localProviders/local?action=login" &&
      jsondecode(data.http.rancher_login.request_body).username == "meshstack-downstream" &&
      jsondecode(data.http.rancher_login.request_body).ttl == 7200000 &&
      jsondecode(data.http.rancher_login.request_body).responseType == "json"
    )
    error_message = "The run must log in as meshstack-downstream with a 2 h token."
  }

  assert {
    condition     = local.rancher_token == "token-abcde:test-token-not-secret"
    error_message = "The rancher2 provider must use the token from the login response."
  }

  assert {
    condition     = output.rancher_cluster_url == "https://rancher.example.com/dashboard/c/c-m-abcd1234/explorer"
    error_message = "rancher_cluster_url must point at the cluster explorer."
  }

  assert {
    condition     = output.nat_public_ip == "203.0.113.70" && output.rancher_cluster_id == "c-m-abcd1234"
    error_message = "NAT IP and cluster ID must be output."
  }

  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.nodes_self.referenced_security_group_id) > 0 &&
      aws_vpc_security_group_ingress_rule.nodes_self.cidr_ipv4 == null
    )
    error_message = "Ingress must come from the cluster's own nodes only; nothing is opened to a CIDR."
  }
}

run "five_control_plane_nodes_in_two_azs" {
  command = plan

  variables {
    control_plane_count = "5"
    worker_count        = 1
    availability_zones  = ["eu-central-1a", "eu-central-1b"]
  }

  assert {
    condition = (
      local.pools["control-plane-eu-central-1a"].quantity == 3 &&
      local.pools["control-plane-eu-central-1b"].quantity == 2 &&
      local.pools["worker-eu-central-1a"].quantity == 1 &&
      !contains(keys(local.pools), "worker-eu-central-1b")
    )
    error_message = "5 control-plane nodes over 2 AZs must split 3+2; 1 worker goes to the first AZ only."
  }
}

run "customer_managed_key" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-central-1:123456789012:key/0e4c5a3b-1111-2222-3333-444455556666"
  }

  assert {
    condition     = alltrue([for k, m in rancher2_machine_config_v2.pool : m.amazonec2_config[0].kms_key == "arn:aws:kms:eu-central-1:123456789012:key/0e4c5a3b-1111-2222-3333-444455556666"])
    error_message = "kms_key_arn must reach every machine config."
  }
}

run "rejects_foreign_account_credentials" {
  command = plan

  variables {
    aws_account_id = "210987654321"
  }

  expect_failures = [data.http.rancher_login, aws_vpc.this]
}

run "rejects_failed_login" {
  command = plan

  override_data {
    target = data.http.rancher_login
    values = {
      status_code   = 401
      response_body = "{\"type\":\"error\",\"status\":\"401\",\"message\":\"must authenticate\"}"
    }
  }

  expect_failures = [data.http.rancher_login]
}
