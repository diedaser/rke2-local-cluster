# Readiness is polled, not slept (ADR-007). Authenticates with the admin
# client certificate and verifies the API server against the cluster CA.
# 90 attempts x 10 s = 15 minutes for cloud-init, RKE2 install and etcd.

data "http" "api_readyz" {
  url                = "${local.api_server_url}/readyz"
  ca_cert_pem        = tls_self_signed_cert.ca["server-ca"].cert_pem
  client_cert_pem    = tls_locally_signed_cert.admin.cert_pem
  client_key_pem     = tls_private_key.admin.private_key_pem
  request_timeout_ms = 10000

  retry {
    attempts     = 90
    min_delay_ms = 10000
    max_delay_ms = 10000
  }

  depends_on = [
    module.server_init,
    module.server_join,
    openstack_lb_members_v2.this,
    openstack_networking_floatingip_associate_v2.lb,
  ]

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "The Kubernetes API at ${local.api_server_url}/readyz did not become ready (HTTP ${self.status_code}). Check that the runner can reach 6443 on the LB (runner_egress_cidrs) and see docs/troubleshooting.md."
    }
  }
}
