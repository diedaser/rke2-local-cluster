variable "account_id" {
  description = "AWS account ID the clusters are created in (the meshStack tenant's account)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12 digit AWS account ID."
  }
}

variable "region" {
  description = "AWS region the clusters are created in. Handed over to the meshStack definition (AWS_REGION); the runner policy is restricted to it."
  type        = string

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", var.region))
    error_message = "region must be an AWS region such as eu-central-1."
  }
}

variable "iam_user_name" {
  description = "Name of the IAM user used by the meshStack runner."
  type        = string
  default     = "meshstack-rke2-runner"
}

variable "kms_key_arn" {
  description = "Optional customer managed KMS key ARN the building blocks use (kms_key_arn input). Grants the runner use of that key."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}

variable "state_encryption_passphrase" {
  description = "Passphrase for OpenTofu state encryption. The state holds the secret access key. Set TF_VAR_state_encryption_passphrase."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.state_encryption_passphrase) >= 16
    error_message = "state_encryption_passphrase must be at least 16 characters."
  }
}
