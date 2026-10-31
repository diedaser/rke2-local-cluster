# meshStack shows outputs in plaintext and has no sensitive outputs.
# Nothing secret leaves this building block (ADR-012, CONTRIBUTING.md rule 11).
# Update values/, README.md and docs/meshstack-gui-setup.md when outputs change.

output "rancher_url" {
  description = "URL of the Rancher UI."
  value       = local.rancher_url
}

output "admin_secret_ref" {
  description = "Barbican reference (URL) of the secret holding the Rancher admin URL, username, password and API token (JSON)."
  value       = openstack_keymanager_secret_v1.admin.secret_ref
}

output "admin_secret_name" {
  description = "Name of the Barbican secret holding the Rancher admin credentials."
  value       = openstack_keymanager_secret_v1.admin.name
}

output "summary" {
  description = "Markdown summary shown in meshStack after apply."
  value = templatefile("${path.module}/templates/summary.md.tftpl", {
    rancher_url          = local.rancher_url
    rancher_version      = var.rancher_version
    cert_manager_version = var.cert_manager_version
    tls_source           = var.tls_source
    replicas             = var.replicas
    admin_secret_name    = openstack_keymanager_secret_v1.admin.name
    admin_secret_ref     = openstack_keymanager_secret_v1.admin.secret_ref
  })
}
