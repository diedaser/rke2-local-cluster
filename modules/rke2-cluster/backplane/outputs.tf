# Paste these into the meshStack definitions as static inputs, Provided as:
# Environment, named in upper case (os_auth_url -> OS_AUTH_URL). Read them with
# `tofu output -json`; never save them in the repo.

output "os_auth_url" {
  description = "Keystone URL (not secret)."
  value       = var.auth_url
}

output "os_region_name" {
  description = "OpenStack region (not secret)."
  value       = var.region
}

output "os_auth_type" {
  description = "Authentication type (not secret)."
  value       = "v3applicationcredential"
}

output "os_application_credential_id" {
  description = "Application credential ID (encrypted input in meshStack)."
  value       = openstack_identity_application_credential_v3.meshstack_runner.id
  sensitive   = true
}

output "os_application_credential_secret" {
  description = "Application credential secret (encrypted input in meshStack)."
  value       = openstack_identity_application_credential_v3.meshstack_runner.secret
  sensitive   = true
}
