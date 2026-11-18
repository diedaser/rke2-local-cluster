# Renders cloud-init per node role. All nodes of a role share one rendering;
# node names are the EC2 private DNS hostnames (ip-a-b-c-d).

locals {
  rke2_tls_dir = "/var/lib/rancher/rke2/server/tls"

  cis_sysctl_file = {
    path        = "/etc/sysctl.d/90-rke2-cis.conf"
    permissions = "0644"
    content     = <<-EOT
      vm.panic_on_oom=0
      vm.overcommit_memory=1
      kernel.panic=10
      kernel.panic_on_oops=1
    EOT
  }

  # With the CIS profile RKE2 enforces the "restricted" Pod Security Standard.
  # Rancher, Fleet and cert-manager namespaces are exempted, following the
  # rancher-restricted template from the Rancher hardening guide.
  psa_config_path = "/etc/rancher/rke2/rancher-psa.yaml"
  psa_config_file = {
    path        = local.psa_config_path
    permissions = "0600"
    content = yamlencode({
      apiVersion = "apiserver.config.k8s.io/v1"
      kind       = "AdmissionConfiguration"
      plugins = [{
        name = "PodSecurity"
        configuration = {
          apiVersion = "pod-security.admission.config.k8s.io/v1"
          kind       = "PodSecurityConfiguration"
          defaults = {
            enforce = "restricted", "enforce-version" = "latest"
            audit   = "restricted", "audit-version" = "latest"
            warn    = "restricted", "warn-version" = "latest"
          }
          exemptions = {
            usernames      = []
            runtimeClasses = []
            namespaces = [
              "calico-apiserver", "calico-system", "cattle-alerting", "cattle-csp-adapter-system",
              "cattle-elemental-system", "cattle-epinio-system", "cattle-externalip-system",
              "cattle-fleet-local-system", "cattle-fleet-system", "cattle-gatekeeper-system",
              "cattle-global-data", "cattle-global-nt", "cattle-impersonation-system",
              "cattle-istio", "cattle-istio-system", "cattle-logging", "cattle-logging-system",
              "cattle-monitoring-system", "cattle-neuvector-system", "cattle-prometheus",
              "cattle-provisioning-capi-system", "cattle-resources-system", "cattle-sriov-system",
              "cattle-system", "cattle-ui-plugin-system", "cattle-windows-gmsa-system",
              "cert-manager", "cis-operator-system", "fleet-default", "ingress-nginx",
              "istio-system", "kube-node-lease", "kube-public", "kube-system", "longhorn-system",
              "rancher-alerting-drivers", "security-scan", "tigera-operator",
            ]
          }
        }
      }]
    })
  }

  # Custom CA files, written on the first server only (ADR-003).
  ca_files = concat(
    flatten([for name, path in local.cluster_cas : [
      {
        path        = "${local.rke2_tls_dir}/${path}.crt"
        permissions = "0644"
        content     = tls_self_signed_cert.ca[name].cert_pem
      },
      {
        path        = "${local.rke2_tls_dir}/${path}.key"
        permissions = "0600"
        content     = tls_private_key.ca[name].private_key_pem
      },
    ]]),
    [{
      path        = "${local.rke2_tls_dir}/service.key"
      permissions = "0600"
      content     = tls_private_key.service_account.private_key_pem
    }],
  )

  server_config_common = {
    registration_url            = local.registration_url
    tls_sans                    = local.tls_sans
    ingress_controller          = var.ingress_controller
    cis_enabled                 = local.cis_enabled
    psa_config_path             = local.psa_config_path
    etcd_snapshot_schedule_cron = var.etcd_snapshot_schedule_cron
    etcd_snapshot_retention     = var.etcd_snapshot_retention
    node_labels                 = local.node_labels
  }

  rke2_config = {
    server_init = templatefile("${path.module}/templates/rke2-server-config.yaml.tftpl", merge(local.server_config_common, {
      first_server = true
      token        = local.rke2_token_secret
    }))
    server_join = templatefile("${path.module}/templates/rke2-server-config.yaml.tftpl", merge(local.server_config_common, {
      first_server = false
      token        = local.rke2_join_token
    }))
    agent = templatefile("${path.module}/templates/rke2-agent-config.yaml.tftpl", {
      registration_url = local.registration_url
      token            = local.rke2_join_token
      cis_enabled      = local.cis_enabled
      node_labels      = local.node_labels
    })
  }

  node_roles = {
    server_init = { role = "server", extra_files = concat(local.cis_enabled ? [local.psa_config_file] : [], local.ca_files) }
    server_join = { role = "server", extra_files = local.cis_enabled ? [local.psa_config_file] : [] }
    agent       = { role = "agent", extra_files = [] }
  }
}

locals {
  cloud_config = {
    for name, node in local.node_roles : name => templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
      role               = node.role
      rke2_version       = var.rke2_version
      install_script_url = var.rke2_install_script_url
      cis_enabled        = local.cis_enabled
      files = concat(
        [{
          path        = "/etc/rancher/rke2/config.yaml"
          permissions = "0600"
          content     = local.rke2_config[name]
        }],
        local.cis_enabled ? [local.cis_sysctl_file] : [],
        node.extra_files,
      )
    })
  }
}

# gzip + base64: EC2 limits user data to 16 KiB, and the first server carries
# the whole CA set. cloud-init decompresses it transparently.
data "cloudinit_config" "node" {
  for_each = local.node_roles

  gzip          = true
  base64_encode = true

  part {
    content_type = "text/cloud-config"
    filename     = "rke2-${each.key}.yaml"
    content      = local.cloud_config[each.key]
  }

  lifecycle {
    postcondition {
      # 16384 bytes raw = 21848 base64 characters.
      condition     = length(self.rendered) <= 21848
      error_message = "cloud-init user data for ${each.key} exceeds the EC2 limit of 16 KiB."
    }
  }
}
