# Resource topology and conditional resources, with mocked providers.
# tls, random and cloudinit run for real: they are local and touch no infra.

mock_provider "openstack" {
  mock_data "openstack_identity_auth_scope_v3" {
    defaults = {
      project_id = "0123456789abcdef0123456789abcdef"
    }
  }
  mock_data "openstack_networking_network_v2" {
    defaults = {
      id = "ext-net-id"
    }
  }
  mock_resource "openstack_lb_loadbalancer_v2" {
    defaults = {
      vip_address = "192.168.42.10"
      vip_port_id = "vip-port-id"
    }
  }
  mock_resource "openstack_networking_floatingip_v2" {
    defaults = {
      address = "203.0.113.50"
    }
  }
  mock_resource "openstack_networking_secgroup_v2" {
    defaults = {
      id = "sg-id"
    }
  }
  mock_resource "openstack_compute_instance_v2" {
    defaults = {
      access_ip_v4 = "192.168.42.20"
    }
  }
  mock_resource "openstack_keymanager_secret_v1" {
    defaults = {
      secret_ref = "https://barbican.example.com/v1/secrets/00000000-0000-0000-0000-000000000000"
    }
  }
}

mock_provider "http" {
  mock_data "http" {
    defaults = {
      status_code   = 200
      response_body = "ok"
    }
  }
}

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
  runner_egress_cidrs         = ["198.51.100.7/32"]
}

run "default_topology" {
  command = apply

  assert {
    condition     = length(module.server_init.ids) == 1 && length(module.server_join.ids) == 2
    error_message = "Default must create 1 initial + 2 joining servers."
  }

  assert {
    condition     = length(module.agents.ids) == 0
    error_message = "No agents by default."
  }

  assert {
    condition     = output.api_server_url == "https://203.0.113.50:6443"
    error_message = "API URL must use the floating IP."
  }

  assert {
    condition     = output.lb_ip == "203.0.113.50"
    error_message = "lb_ip must be the floating IP."
  }

  assert {
    condition     = output.kubeconfig_secret_name == "mgmt-3f2b8c1e-kubeconfig"
    error_message = "Kubeconfig secret name must derive from cluster name and BB UUID."
  }

  assert {
    condition     = toset(keys(openstack_lb_listener_v2.this)) == toset(["api", "supervisor", "http", "https"])
    error_message = "LB must have listeners for 6443, 9345, 80, 443."
  }

  assert {
    condition     = tolist(openstack_lb_listener_v2.this["supervisor"].allowed_cidrs) == tolist(["192.168.42.0/24"])
    error_message = "Supervisor port must only be reachable from the cluster subnet."
  }

  assert {
    condition     = contains(tolist(openstack_lb_listener_v2.this["api"].allowed_cidrs), "198.51.100.7/32")
    error_message = "Runner egress CIDRs must be allowed on the API listener."
  }

  assert {
    condition     = length(local.listeners["api"].members) == 3
    error_message = "API pool must contain all three servers."
  }

  assert {
    condition     = length(openstack_networking_secgroup_rule_v2.ssh) == 0
    error_message = "No SSH rule without ssh_allowed_cidrs."
  }
}

run "cloud_init_content" {
  command = apply

  assert {
    condition     = alltrue([for k, v in local.cloud_config : can(yamldecode(v))]) && alltrue([for k, v in local.rke2_config : can(yamldecode(v))])
    error_message = "Rendered cloud-config and RKE2 config must be valid YAML."
  }

  assert {
    condition     = yamldecode(local.cloud_config["server_init"]).write_files[0].path == "/etc/rancher/rke2/config.yaml"
    error_message = "cloud-config must write the RKE2 config first."
  }

  # First server: CA files and no server: key. Joining servers: server: key, no CA keys.
  assert {
    condition     = strcontains(data.cloudinit_config.node["server_init"].rendered, "/var/lib/rancher/rke2/server/tls/server-ca.key")
    error_message = "First server must receive the custom CA keys."
  }

  assert {
    condition     = !strcontains(data.cloudinit_config.node["server_join"].rendered, "server-ca.key")
    error_message = "Joining servers must not receive CA keys."
  }

  assert {
    condition     = strcontains(local.rke2_config["server_join"], "server: \"https://192.168.42.10:9345\"")
    error_message = "Joining servers must register through the LB VIP on 9345."
  }

  assert {
    condition     = !can(regex("(?m)^server:", local.rke2_config["server_init"]))
    error_message = "First server must not have a server: key."
  }

  assert {
    condition     = strcontains(local.rke2_config["server_init"], "profile: cis")
    error_message = "CIS profile must be enabled by default."
  }

  assert {
    condition     = strcontains(local.rke2_config["server_init"], "ingress-controller: \"ingress-nginx\"")
    error_message = "Ingress controller must be set explicitly."
  }

  assert {
    condition     = strcontains(local.rke2_config["server_init"], "203.0.113.50") && strcontains(local.rke2_config["server_init"], "192.168.42.10")
    error_message = "tls-san must contain the VIP and the floating IP."
  }

  assert {
    condition     = startswith(local.rke2_join_token, "K10") && strcontains(local.rke2_join_token, "::server:")
    error_message = "Join token must pin the cluster CA."
  }

  assert {
    condition     = strcontains(data.cloudinit_config.node["server_init"].rendered, "INSTALL_RKE2_VERSION='v1.35.9+rke2r1'")
    error_message = "RKE2 version must be pinned in the install command."
  }
}

run "admin_certificate" {
  command = apply

  assert {
    condition     = tls_cert_request.admin.subject[0].organization == "system:masters"
    error_message = "Admin cert must be in system:masters."
  }

  assert {
    condition     = tls_locally_signed_cert.admin.ca_cert_pem == tls_self_signed_cert.ca["client-ca"].cert_pem
    error_message = "Admin cert must be signed by the client CA."
  }

  assert {
    condition     = tls_locally_signed_cert.admin.early_renewal_hours == 720
    error_message = "Default early renewal is 30 days."
  }

  assert {
    condition     = strcontains(local.kubeconfig, "https://203.0.113.50:6443")
    error_message = "Kubeconfig must point at the API URL."
  }
}

run "dev_single_server_with_agents" {
  command = apply

  variables {
    server_count      = "1"
    agent_count       = 2
    hardening_profile = "none"
    ssh_allowed_cidrs = ["10.1.0.0/24"]
  }

  assert {
    condition     = length(module.server_join.ids) == 0
    error_message = "server_count 1 must not create joining servers."
  }

  assert {
    condition     = length(module.agents.ids) == 2
    error_message = "agent_count must create agents."
  }

  assert {
    condition     = length(local.listeners["https"].members) == 3
    error_message = "Ingress pools must include servers and agents."
  }

  assert {
    condition     = !strcontains(local.rke2_config["server_init"], "profile:")
    error_message = "hardening_profile none must not set a profile."
  }

  assert {
    condition     = !strcontains(data.cloudinit_config.node["server_init"].rendered, "rancher-psa.yaml")
    error_message = "PSA config is only written with the CIS profile."
  }

  assert {
    condition     = length(openstack_networking_secgroup_rule_v2.ssh) == 1
    error_message = "ssh_allowed_cidrs must create SSH rules."
  }
}

run "no_floating_ip" {
  command = apply

  variables {
    assign_floating_ip = false
  }

  assert {
    condition     = length(openstack_networking_floatingip_v2.lb) == 0
    error_message = "No floating IP when disabled."
  }

  assert {
    condition     = output.api_server_url == "https://192.168.42.10:6443"
    error_message = "API URL must use the VIP without floating IP."
  }
}

run "rejects_foreign_project_credentials" {
  command = plan

  variables {
    openstack_project_id = "ffffffffffffffffffffffffffffffff"
  }

  expect_failures = [openstack_networking_network_v2.this]
}
