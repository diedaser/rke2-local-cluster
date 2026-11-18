# meshStack shows outputs in plaintext and has no sensitive outputs.
# Nothing secret leaves this building block (ADR-012, CONTRIBUTING.md rule 11).
# Update templates/summary.md.tftpl, README.md and docs/meshstack-gui-setup.md
# when outputs change.

output "kubeconfig_secret_name" {
  description = "Name of the AWS Secrets Manager secret holding the admin kubeconfig. Consumed by the `rancher` building block."
  value       = aws_secretsmanager_secret.kubeconfig.name
}

output "kubeconfig_secret_arn" {
  description = "ARN of the admin kubeconfig secret (informational)."
  value       = aws_secretsmanager_secret.kubeconfig.arn
}

output "api_server_url" {
  description = "Kubernetes API URL through the client-facing load balancer."
  value       = local.api_server_url
}

output "lb_dns_name" {
  description = "DNS name of the client-facing NLB (public, or internal if public_load_balancer = false). Point the Rancher DNS record (CNAME or Route 53 alias) here."
  value       = local.client_lb_dns
}

output "summary" {
  description = "Markdown summary shown in meshStack after apply."
  value = templatefile("${path.module}/templates/summary.md.tftpl", {
    cluster_name           = var.cluster_name
    api_server_url         = local.api_server_url
    lb_dns_name            = local.client_lb_dns
    internal_lb_dns_name   = local.internal_lb_dns
    public_load_balancer   = var.public_load_balancer
    region                 = aws_secretsmanager_secret.kubeconfig.region
    rke2_version           = var.rke2_version
    server_count           = local.server_count
    agent_count            = var.agent_count
    hardening_profile      = var.hardening_profile
    ingress_controller     = var.ingress_controller
    kubeconfig_secret_name = aws_secretsmanager_secret.kubeconfig.name
    kubeconfig_secret_arn  = aws_secretsmanager_secret.kubeconfig.arn
    admin_cert_expiry      = tls_locally_signed_cert.admin.validity_end_time
  })
}
