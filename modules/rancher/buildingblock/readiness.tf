# Readiness is polled, not slept (ADR-007).

# The cluster API must answer before any Kubernetes or Helm resource.
data "http" "api_readyz" {
  url                = "${var.api_server_url}/readyz"
  ca_cert_pem        = local.kube_cluster_ca_certificate
  client_cert_pem    = local.kube_client_certificate
  client_key_pem     = local.kube_client_key
  request_timeout_ms = 10000

  retry {
    attempts     = 30
    min_delay_ms = 10000
    max_delay_ms = 10000
  }

  lifecycle {
    precondition {
      condition     = data.openstack_identity_auth_scope_v3.current.project_id == var.openstack_project_id
      error_message = "The OpenStack credentials are scoped to project ${data.openstack_identity_auth_scope_v3.current.project_id}, but the meshStack tenant is ${var.openstack_project_id} (see ADR-013)."
    }
    postcondition {
      condition     = self.status_code == 200
      error_message = "The Kubernetes API at ${var.api_server_url} is not ready (HTTP ${self.status_code}). Check runner reachability on 6443 and docs/troubleshooting.md."
    }
  }
}

# Rancher must answer on its hostname before bootstrap. This also proves DNS
# and the LB path for 443 work from the runner. Certificate verification is
# irrelevant for readiness, so it is skipped (Let's Encrypt may still be issuing).
data "http" "rancher_ping" {
  url                = "${local.rancher_url}/ping"
  insecure           = true
  request_timeout_ms = 10000

  retry {
    attempts     = 60
    min_delay_ms = 10000
    max_delay_ms = 10000
  }

  depends_on = [helm_release.rancher]

  lifecycle {
    postcondition {
      condition     = self.status_code == 200 && trimspace(self.response_body) == "pong"
      error_message = "Rancher at ${local.rancher_url}/ping did not answer 'pong' (HTTP ${self.status_code}). Check the DNS record for ${var.rancher_hostname} and runner reachability on 443."
    }
  }
}
