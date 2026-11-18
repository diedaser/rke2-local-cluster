# Paste these into the meshStack definitions as static inputs, Provided as:
# Environment, named in upper case (aws_region -> AWS_REGION). Read them with
# `tofu output -json`; never save them in the repo.

output "aws_region" {
  description = "AWS region (not secret)."
  value       = var.region
}

output "aws_access_key_id" {
  description = "Access key ID of the runner IAM user (encrypted input in meshStack)."
  value       = aws_iam_access_key.meshstack_runner.id
  sensitive   = true
}

output "aws_secret_access_key" {
  description = "Secret access key of the runner IAM user (encrypted input in meshStack)."
  value       = aws_iam_access_key.meshstack_runner.secret
  sensitive   = true
}

output "aws_account_id" {
  description = "AWS account ID; the meshStack Platform Tenant ID of the tenants served by this credential (ADR-013)."
  value       = local.account_id
}
