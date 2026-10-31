# meshStack shows outputs in plaintext and has no sensitive outputs.
# Nothing secret leaves this building block (ADR-012, CONTRIBUTING.md rule 11).
# Update templates/summary.md.tftpl, README.md and docs/meshstack-gui-setup.md
# when outputs change.

output "kubeconfig_secret_name" {
  description = "Name of the Barbican secret holding the admin kubeconfig. Consumed by the `rancher` building block."
  value       = openstack_keymanager_secret_v1.kubeconfig.name
}

output "kubeconfig_secret_ref" {
  description = "Barbican reference (URL) of the admin kubeconfig secret."
  value       = openstack_keymanager_secret_v1.kubeconfig.secret_ref
}

output "api_server_url" {
  description = "Kubernetes API URL through the load balancer."
  value       = local.api_server_url
}

output "lb_ip" {
  description = "Client-facing IP of the load balancer (floating IP, or VIP if no floating IP is assigned). Point the Rancher DNS record here."
  value       = local.lb_public_ip
}

output "summary" {
  description = "Markdown summary shown in meshStack after apply."
  value = templatefile("${path.module}/templates/summary.md.tftpl", {
    cluster_name           = var.cluster_name
    api_server_url         = local.api_server_url
    lb_ip                  = local.lb_public_ip
    lb_vip                 = local.lb_vip_address
    rke2_version           = var.rke2_version
    server_count           = local.server_count
    agent_count            = var.agent_count
    hardening_profile      = var.hardening_profile
    ingress_controller     = var.ingress_controller
    kubeconfig_secret_name = openstack_keymanager_secret_v1.kubeconfig.name
    kubeconfig_secret_ref  = openstack_keymanager_secret_v1.kubeconfig.secret_ref
    admin_cert_expiry      = tls_locally_signed_cert.admin.validity_end_time
  })
}
