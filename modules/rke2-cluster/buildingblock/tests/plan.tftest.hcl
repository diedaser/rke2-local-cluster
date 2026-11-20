# Resource topology and conditional resources, with mocked providers.
# tls, random and cloudinit run for real: they are local and touch no infra.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn    = "arn:aws:s3:::rke2-backup-mock"
      region = "eu-central-1"
    }
  }
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["eu-central-1c", "eu-central-1a", "eu-central-1b"]
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
  mock_resource "aws_instance" {
    defaults = {
      private_ip = "10.100.0.20"
    }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn    = "arn:aws:secretsmanager:eu-central-1:123456789012:secret:mgmt-3f2b8c1e-kubeconfig-AbCdEf"
      region = "eu-central-1"
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

override_resource {
  target = aws_lb.internal
  values = {
    dns_name = "rke2-3f2b8c1e-internal-0123456789.elb.eu-central-1.amazonaws.com"
    arn      = "arn:aws:elasticloadbalancing:eu-central-1:123456789012:loadbalancer/net/rke2-3f2b8c1e-internal/0123456789abcdef"
  }
}

override_resource {
  target = aws_lb.public
  values = {
    dns_name = "rke2-3f2b8c1e-public-0123456789.elb.eu-central-1.amazonaws.com"
    arn      = "arn:aws:elasticloadbalancing:eu-central-1:123456789012:loadbalancer/net/rke2-3f2b8c1e-public/0123456789abcdef"
  }
}

variables {
  workspace_identifier        = "platform"
  project_identifier          = "rancher-mgmt"
  building_block_uuid         = "3f2b8c1e-1234-4abc-9def-0123456789ab"
  aws_account_id              = "123456789012"
  state_encryption_passphrase = "test-passphrase-not-secret"
  cluster_name                = "mgmt"
  ami_id                      = "ami-0123456789abcdef0"
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
    condition     = local.azs == tolist(["eu-central-1a", "eu-central-1b", "eu-central-1c"])
    error_message = "Default AZs must be the first three of the region, sorted."
  }

  assert {
    condition     = aws_subnet.private["eu-central-1a"].cidr_block == "10.100.0.0/19" && aws_subnet.public["eu-central-1a"].cidr_block == "10.100.128.0/19"
    error_message = "Subnets must follow the 8-way VPC split (private 0-3, public 4-7)."
  }

  assert {
    condition     = tolist(module.server_join.names) == tolist(["mgmt-3f2b8c1e-server-01", "mgmt-3f2b8c1e-server-02"])
    error_message = "Joining servers must continue the numbering after the first server."
  }

  assert {
    condition     = output.api_server_url == "https://rke2-3f2b8c1e-public-0123456789.elb.eu-central-1.amazonaws.com:6443"
    error_message = "API URL must use the public NLB."
  }

  assert {
    condition     = output.lb_dns_name == "rke2-3f2b8c1e-public-0123456789.elb.eu-central-1.amazonaws.com"
    error_message = "lb_dns_name must be the public NLB."
  }

  assert {
    condition     = output.kubeconfig_secret_name == "mgmt-3f2b8c1e-kubeconfig"
    error_message = "Kubeconfig secret name must derive from cluster name and BB UUID."
  }

  assert {
    condition     = toset(keys(aws_lb_listener.this)) == toset(["int-api", "int-sup", "pub-api", "pub-http", "pub-https"])
    error_message = "Internal NLB must serve 6443/9345, public NLB 6443/80/443."
  }

  assert {
    condition     = aws_lb.internal.internal && !aws_lb.public[0].internal
    error_message = "NLB schemes must be internal and internet-facing."
  }

  assert {
    condition     = length(local.listeners["int-sup"].cidrs) == 0 && length(local.listeners["int-api"].cidrs) == 0
    error_message = "Internal API and supervisor must admit no CIDR with a public NLB, only the management nodes (lb_internal_from_nodes)."
  }

  assert {
    condition     = contains(local.listeners["pub-api"].cidrs, "198.51.100.7/32") && contains(local.listeners["pub-https"].cidrs, "198.51.100.7/32")
    error_message = "Runner egress CIDRs must be allowed on the public API and HTTPS listeners."
  }

  assert {
    condition     = !contains(local.listeners["pub-api"].cidrs, "10.100.0.0/16")
    error_message = "The VPC CIDR is meaningless on the internet-facing NLB."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.lb_public_from_nat) == 3
    error_message = "The NAT EIP must reach the public NLB (pod hairpin to the Rancher hostname)."
  }

  assert {
    condition     = alltrue([for tg in aws_lb_target_group.this : !tg.preserve_client_ip])
    error_message = "Client IP preservation must be off (hairpin through the NLB)."
  }

  assert {
    condition     = length([for k, v in local.attachments : k if v.listener == "int-api"]) == 3
    error_message = "API target group must contain all three servers."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.ssh) == 0
    error_message = "No SSH rule without ssh_allowed_cidrs."
  }

  assert {
    condition     = aws_placement_group.servers.strategy == "spread"
    error_message = "Servers must use a spread placement group."
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
    condition     = strcontains(local.cloud_config["server_init"], "/var/lib/rancher/rke2/server/tls/server-ca.key")
    error_message = "First server must receive the custom CA keys."
  }

  assert {
    condition     = !strcontains(local.cloud_config["server_join"], "server-ca.key")
    error_message = "Joining servers must not receive CA keys."
  }

  assert {
    condition     = strcontains(local.rke2_config["server_join"], "server: \"https://rke2-3f2b8c1e-internal-0123456789.elb.eu-central-1.amazonaws.com:9345\"")
    error_message = "Joining servers must register through the internal NLB on 9345."
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
    condition     = strcontains(local.rke2_config["server_init"], "ingress-controller: \"traefik\"")
    error_message = "Ingress controller must be set explicitly."
  }

  assert {
    condition     = strcontains(local.rke2_config["server_init"], "rke2-3f2b8c1e-public-") && strcontains(local.rke2_config["server_init"], "rke2-3f2b8c1e-internal-")
    error_message = "tls-san must contain both NLB DNS names."
  }

  assert {
    condition     = startswith(local.rke2_join_token, "K10") && strcontains(local.rke2_join_token, "::server:")
    error_message = "Join token must pin the cluster CA."
  }

  assert {
    condition     = strcontains(local.cloud_config["server_init"], "INSTALL_RKE2_VERSION='v1.36.6+rke2r1'")
    error_message = "RKE2 version must be pinned in the install command."
  }

  assert {
    condition     = alltrue([for k, v in data.cloudinit_config.node : length(v.rendered) <= 21848])
    error_message = "User data must fit the EC2 16 KiB limit."
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
    condition     = strcontains(local.kubeconfig, "https://rke2-3f2b8c1e-public-0123456789.elb.eu-central-1.amazonaws.com:6443")
    error_message = "Kubeconfig must point at the API URL."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.kubeconfig.secret_string == local.kubeconfig
    error_message = "The kubeconfig must be stored in Secrets Manager."
  }
}

run "dev_single_server_with_agents" {
  command = apply

  variables {
    server_count       = "1"
    agent_count        = 2
    hardening_profile  = "none"
    ssh_allowed_cidrs  = ["10.1.0.0/24"]
    availability_zones = ["eu-central-1a"]
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
    condition     = length([for k, v in local.attachments : k if v.listener == "pub-https"]) == 3
    error_message = "Ingress target groups must include servers and agents."
  }

  assert {
    condition     = length([for k, v in local.attachments : k if v.listener == "int-sup"]) == 1
    error_message = "Supervisor target group must include servers only."
  }

  assert {
    condition     = tolist(keys(aws_subnet.private)) == tolist(["eu-central-1a"])
    error_message = "availability_zones must override the region default."
  }

  assert {
    condition     = !strcontains(local.rke2_config["server_init"], "profile:")
    error_message = "hardening_profile none must not set a profile."
  }

  assert {
    condition     = !strcontains(local.cloud_config["server_init"], "rancher-psa.yaml")
    error_message = "PSA config is only written with the CIS profile."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.ssh) == 1
    error_message = "ssh_allowed_cidrs must create SSH rules."
  }
}

run "backups" {
  command = apply

  variables {
    agent_count = 1
  }

  assert {
    condition     = aws_s3_bucket.backup.bucket == "rke2-backup-3f2b8c1e-123456789012"
    error_message = "Backup bucket name must follow rke2-backup-<short_id>-<account> (backplane IAM scope)."
  }

  assert {
    condition     = aws_s3_bucket.backup.force_destroy == false
    error_message = "Backups must survive a building block delete by default."
  }

  assert {
    condition     = aws_iam_role.server.path == "/rke2/" && aws_iam_instance_profile.server.path == "/rke2/"
    error_message = "IAM role and instance profile must live under /rke2/ (backplane IAM scope)."
  }

  assert {
    condition     = aws_iam_role.server.permissions_boundary == "arn:aws:iam::123456789012:policy/rke2/rke2-backup-boundary"
    error_message = "The server role must carry the backplane permissions boundary, or the runner is denied CreateRole."
  }

  assert {
    condition     = module.server_init.iam_instance_profile == aws_iam_instance_profile.server.name && module.server_join.iam_instance_profile == aws_iam_instance_profile.server.name
    error_message = "Servers must carry the etcd snapshot instance profile."
  }

  assert {
    condition     = module.agents.iam_instance_profile == null
    error_message = "Agents must not get S3 access."
  }

  assert {
    condition = alltrue([for role in ["server_init", "server_join"] : alltrue([
      strcontains(local.rke2_config[role], "etcd-s3: true"),
      strcontains(local.rke2_config[role], "etcd-s3-bucket: \"rke2-backup-3f2b8c1e-123456789012\""),
      strcontains(local.rke2_config[role], "etcd-s3-region: \"eu-central-1\""),
      strcontains(local.rke2_config[role], "etcd-s3-endpoint: \"s3.eu-central-1.amazonaws.com\""),
      strcontains(local.rke2_config[role], "etcd-s3-folder: \"etcd\""),
      strcontains(local.rke2_config[role], "etcd-snapshot-retention: 10"),
    ])])
    error_message = "Every server must upload etcd snapshots to the backup bucket and keep 10."
  }

  assert {
    condition     = !strcontains(local.rke2_config["server_init"], "etcd-s3-access-key")
    error_message = "etcd S3 must use the instance profile, never a static key."
  }
}

run "backup_force_destroy" {
  command = plan

  variables {
    backup_force_destroy = true
  }

  assert {
    condition     = aws_s3_bucket.backup.force_destroy == true
    error_message = "backup_force_destroy must reach the bucket."
  }
}

run "internal_only" {
  command = apply

  variables {
    public_load_balancer = false
  }

  assert {
    condition     = length(aws_lb.public) == 0
    error_message = "No public NLB when disabled."
  }

  assert {
    condition     = toset(keys(aws_lb_listener.this)) == toset(["int-api", "int-sup", "int-http", "int-https"])
    error_message = "Internal NLB must serve clients on 6443/80/443 without a public NLB."
  }

  assert {
    condition     = contains(local.listeners["int-api"].cidrs, "10.0.0.0/8") && !contains(local.listeners["int-api"].cidrs, "10.100.0.0/16")
    error_message = "Internal API listener must allow the clients and the VPC."
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.lb_public_from_nat) == 0
    error_message = "No NAT hairpin rule without a public NLB."
  }

  assert {
    condition     = output.api_server_url == "https://rke2-3f2b8c1e-internal-0123456789.elb.eu-central-1.amazonaws.com:6443"
    error_message = "API URL must use the internal NLB without a public NLB."
  }
}

run "rejects_foreign_account_credentials" {
  command = plan

  variables {
    aws_account_id = "999999999999"
  }

  expect_failures = [aws_vpc.this]
}

run "internal_listeners_admit_management_nodes_only" {
  command = apply

  assert {
    condition = alltrue([for k, r in aws_vpc_security_group_ingress_rule.lb_internal_from_nodes : (
      r.referenced_security_group_id == aws_security_group.nodes.id &&
      r.security_group_id == aws_security_group.lb["internal"].id
    )]) && toset([for r in aws_vpc_security_group_ingress_rule.lb_internal_from_nodes : r.from_port]) == toset([6443, 9345])
    error_message = "The internal API and supervisor listeners must admit the management node security group."
  }

  assert {
    condition     = length([for k, r in aws_vpc_security_group_ingress_rule.lb_clients : k if r.cidr_ipv4 == "10.100.0.0/16" && contains([6443, 9345], r.from_port)]) == 0
    error_message = "The VPC CIDR must not reach the internal API or supervisor: downstream clusters share the VPC (ADR-015)."
  }

  assert {
    condition     = output.vpc_id == aws_vpc.this.id && length(output.private_subnet_ids) == 3
    error_message = "VPC and private subnets must be output for downstream clusters."
  }
}
