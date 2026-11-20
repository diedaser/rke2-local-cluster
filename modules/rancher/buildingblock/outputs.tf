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

# Pass-through for downstream-cluster (meshStack maps only direct-parent
# outputs, ADR-015). Not secret.
output "mgmt_vpc_id" {
  description = "VPC of the management cluster, where downstream clusters place their nodes."
  value       = var.mgmt_vpc_id
}

output "mgmt_private_subnet_ids" {
  description = "Private subnet ID per AZ of the management cluster, for downstream nodes."
  value       = var.mgmt_private_subnet_ids
}

output "downstream_credentials_secret_name" {
  description = "Name of the Secrets Manager secret holding the Rancher login (url, username, password) of the downstream-cluster building block (ADR-015). Consumed by `downstream-cluster`."
  value       = aws_secretsmanager_secret.downstream.name

  # Hand out the name only once the credentials are stored and the user has
  # its roles.
  depends_on = [aws_secretsmanager_secret_version.downstream]
}

output "backup_encryption_secret_name" {
  description = "Name of the Secrets Manager secret holding the EncryptionConfiguration needed to restore the Rancher backups."
  value       = aws_secretsmanager_secret.backup_encryption.name
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
    backup_location      = "s3://${var.backup_bucket_name}/${local.backup_s3_folder}/"
    backup_schedule      = var.rancher_backup_schedule
    backup_retention     = var.rancher_backup_retention
    backup_secret_name   = aws_secretsmanager_secret.backup_encryption.name
    downstream_secret    = aws_secretsmanager_secret.downstream.name
    downstream_username  = rancher2_user.downstream.username
  })
}
