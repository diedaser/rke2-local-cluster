# meshStack shows outputs in plaintext and has no sensitive outputs.
# Nothing secret leaves this building block (ADR-012, CONTRIBUTING.md rule 11).
# Update values/, README.md and docs/meshstack-gui-setup.md when outputs change.

output "rancher_url" {
  description = "URL of the Rancher UI."
  value       = local.rancher_url
}

output "admin_secret_name" {
  description = "Name of the AWS Secrets Manager secret holding the Rancher admin URL, username, password and API token (JSON)."
  value       = aws_secretsmanager_secret.admin.name
}

output "admin_secret_arn" {
  description = "ARN of the Rancher admin credentials secret."
  value       = aws_secretsmanager_secret.admin.arn
}

output "summary" {
  description = "Markdown summary shown in meshStack after apply."
  value = templatefile("${path.module}/templates/summary.md.tftpl", {
    rancher_url          = local.rancher_url
    rancher_version      = var.rancher_version
    cert_manager_version = var.cert_manager_version
    tls_source           = var.tls_source
    replicas             = var.replicas
    admin_secret_name    = aws_secretsmanager_secret.admin.name
    admin_secret_arn     = aws_secretsmanager_secret.admin.arn
    region               = aws_secretsmanager_secret.admin.region
  })
}
