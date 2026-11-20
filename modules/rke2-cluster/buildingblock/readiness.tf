# Readiness is polled, not slept (ADR-007). Authenticates with the admin
# client certificate and verifies the API server against the cluster CA.
# 120 attempts x 10 s = 20 minutes for cloud-init, RKE2 install, etcd and
# NLB target registration (which alone takes several minutes).

data "http" "api_readyz" {
  url                = "${local.api_server_url}/readyz"
  ca_cert_pem        = tls_self_signed_cert.ca["server-ca"].cert_pem
  client_cert_pem    = tls_locally_signed_cert.admin.cert_pem
  client_key_pem     = tls_private_key.admin.private_key_pem
  request_timeout_ms = 10000

  retry {
    attempts     = 120
    min_delay_ms = 10000
    max_delay_ms = 10000
  }

  # Everything on the path client -> NLB -> node must be listed here, directly
  # or through module.server_init (routes, node rules). Consumers of this
  # building block's outputs depend on this check (outputs.tf), so this list
  # also decides what a combined destroy keeps alive until they are gone.
  # Missing nodes_from_lb / lb_public_from_nat / lb_to_vpc let a standalone
  # destroy cut Rancher off while module.rancher was still being destroyed.
  depends_on = [
    module.server_init,
    module.server_join,
    aws_lb_listener.this,
    aws_lb_target_group_attachment.this,
    aws_vpc_security_group_ingress_rule.lb_clients,
    aws_vpc_security_group_ingress_rule.lb_internal_from_nodes,
    aws_vpc_security_group_ingress_rule.lb_public_from_nat,
    aws_vpc_security_group_ingress_rule.nodes_from_lb,
    aws_vpc_security_group_egress_rule.lb_to_vpc,
  ]

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "The Kubernetes API at ${local.api_server_url}/readyz did not become ready (HTTP ${self.status_code}). Check that the runner can reach 6443 on the LB (runner_egress_cidrs) and see docs/troubleshooting.md."
    }
  }
}
