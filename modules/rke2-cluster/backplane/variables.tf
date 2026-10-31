variable "project_id" {
  description = "OpenStack project ID the clusters are created in (the meshStack tenant's project)."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.project_id))
    error_message = "project_id must be a 32 character hex OpenStack project ID."
  }
}

variable "auth_url" {
  description = "Keystone URL to hand over to the meshStack definition (OS_AUTH_URL)."
  type        = string

  validation {
    condition     = startswith(var.auth_url, "https://")
    error_message = "auth_url must be an https URL."
  }
}

variable "region" {
  description = "OpenStack region to hand over to the meshStack definition (OS_REGION_NAME)."
  type        = string
}

variable "application_credential_name" {
  description = "Name of the application credential used by the meshStack runner."
  type        = string
  default     = "meshstack-rke2-runner"
}

variable "roles" {
  description = "Roles the application credential carries. Depending on the cloud's policies, Octavia may need `load-balancer_member` and Barbican `creator`."
  type        = list(string)
  default     = ["member"]

  validation {
    condition     = length(var.roles) > 0
    error_message = "roles must not be empty."
  }
}

variable "expires_at" {
  description = "Optional expiry of the application credential (RFC3339). Rotate before it expires."
  type        = string
  default     = null
}

variable "manage_quotas" {
  description = "Set project quotas (requires admin rights)."
  type        = bool
  default     = false
}

variable "quota" {
  description = "Project quotas used when manage_quotas = true. Defaults fit one 3-server cluster plus headroom for a rolling replacement."
  type = object({
    instances     = optional(number, 10)
    cores         = optional(number, 40)
    ram_mb        = optional(number, 163840)
    volumes       = optional(number, 20)
    volume_gb     = optional(number, 2000)
    floating_ips  = optional(number, 4)
    loadbalancers = optional(number, 2)
  })
  default = {}
}

variable "state_encryption_passphrase" {
  description = "Passphrase for OpenTofu state encryption. The state holds the application credential secret. Set TF_VAR_state_encryption_passphrase."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.state_encryption_passphrase) >= 16
    error_message = "state_encryption_passphrase must be at least 16 characters."
  }
}
