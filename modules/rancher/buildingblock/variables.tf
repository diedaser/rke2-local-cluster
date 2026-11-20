# Every variable maps 1:1 to a meshStack input. Keep docs/meshstack-gui-setup.md
# in sync when adding, removing or retyping variables (CONTRIBUTING.md rule 12).

# --- meshStack context ---------------------------------------------------------

variable "workspace_identifier" {
  description = "meshStack workspace identifier (source: Workspace Identifier)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.workspace_identifier))
    error_message = "workspace_identifier must be a meshStack identifier (lowercase letters, digits, dashes)."
  }
}

variable "project_identifier" {
  description = "meshStack project identifier (source: Project Identifier)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,62}$", var.project_identifier))
    error_message = "project_identifier must be a meshStack identifier (lowercase letters, digits, dashes)."
  }
}

variable "building_block_uuid" {
  description = "meshStack building block UUID (source: Building Block UUID). Makes the admin secret name unique."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{8,}$", var.building_block_uuid))
    error_message = "building_block_uuid must be a UUID."
  }
}

variable "aws_account_id" {
  description = "AWS account ID of the meshStack tenant (source: Platform Tenant ID). Must match the account of the runner credentials."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12 digit AWS account ID."
  }
}

# --- From the parent building block (rke2-cluster) -----------------------------

variable "kubeconfig_secret_name" {
  description = "Name of the AWS Secrets Manager secret holding the cluster admin kubeconfig (source: Parent Building Block Output `kubeconfig_secret_name`)."
  type        = string

  validation {
    condition     = endswith(var.kubeconfig_secret_name, "-kubeconfig")
    error_message = "kubeconfig_secret_name must be the kubeconfig_secret_name output of the rke2-cluster building block."
  }
}

variable "backup_bucket_name" {
  description = "S3 bucket for Rancher backups (source: Parent Building Block Output `backup_bucket_name`). Backups go to the prefix rancher/."
  type        = string

  validation {
    condition     = can(regex("^rke2-backup-[0-9a-f]{8}-[0-9]{12}$", var.backup_bucket_name))
    error_message = "backup_bucket_name must be the backup_bucket_name output of the rke2-cluster building block."
  }
}

variable "api_server_url" {
  description = "Kubernetes API URL (source: Parent Building Block Output `api_server_url`). Polled for readiness before any Kubernetes resource."
  type        = string

  validation {
    condition     = can(regex("^https://[^/]+:[0-9]+$", var.api_server_url))
    error_message = "api_server_url must look like https://<host>:6443."
  }
}

# --- Secrets -------------------------------------------------------------------

variable "state_encryption_passphrase" {
  description = "Passphrase for OpenTofu state encryption (ADR-004). Provided as environment variable TF_VAR_state_encryption_passphrase."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.state_encryption_passphrase) >= 16
    error_message = "state_encryption_passphrase must be at least 16 characters."
  }
}

# --- User inputs ---------------------------------------------------------------

variable "rancher_hostname" {
  description = "FQDN of the Rancher UI. A DNS record pointing at the cluster LB IP must exist before the run."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,}$", var.rancher_hostname))
    error_message = "rancher_hostname must be a lowercase FQDN such as rancher.example.com."
  }
}

variable "tls_source" {
  description = "Source of the Rancher ingress certificate: `rancher` (Rancher-generated CA via cert-manager), `letsEncrypt`, or `secret` (bring your own)."
  type        = string
  default     = "rancher"

  validation {
    condition     = contains(["rancher", "letsEncrypt", "secret"], var.tls_source)
    error_message = "tls_source must be one of rancher, letsEncrypt, secret."
  }
}

variable "letsencrypt_email" {
  description = "Contact e-mail for Let's Encrypt. Required when tls_source = letsEncrypt."
  type        = string
  default     = null

  validation {
    condition     = var.letsencrypt_email == null || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.letsencrypt_email))
    error_message = "letsencrypt_email must be a valid e-mail address."
  }
}

variable "tls_certificate_pem" {
  description = "PEM certificate (with chain) for the Rancher ingress. Required when tls_source = secret."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.tls_certificate_pem == null || can(regex("-----BEGIN CERTIFICATE-----", var.tls_certificate_pem))
    error_message = "tls_certificate_pem must be a PEM encoded certificate."
  }
}

variable "tls_private_key_pem" {
  description = "PEM private key for the Rancher ingress. Required when tls_source = secret."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.tls_private_key_pem == null || can(regex("-----BEGIN [A-Z ]*PRIVATE KEY-----", var.tls_private_key_pem))
    error_message = "tls_private_key_pem must be a PEM encoded private key."
  }
}

# --- Platform-controlled inputs ------------------------------------------------

variable "rancher_version" {
  description = "Rancher Helm chart version. Must support the cluster's RKE2 version (Rancher support matrix)."
  type        = string
  # Rancher v2.15.2 support matrix: local/hosting cluster RKE2 v1.34 - v1.36.
  default = "2.15.2"

  validation {
    condition     = can(regex("^2\\.[0-9]+\\.[0-9]+$", var.rancher_version))
    error_message = "rancher_version must be a pinned chart version such as 2.15.2 (no 'v' prefix, never 'latest')."
  }
}

variable "cert_manager_version" {
  description = "cert-manager Helm chart version."
  type        = string
  default     = "v1.21.2"

  validation {
    condition     = can(regex("^v1\\.[0-9]+\\.[0-9]+$", var.cert_manager_version))
    error_message = "cert_manager_version must be a pinned version such as v1.21.2."
  }
}

variable "rancher_backup_chart_version" {
  description = "rancher-backup and rancher-backup-crd chart version (charts.rancher.io). Must match the Rancher minor (catalog.cattle.io/rancher-version annotation)."
  type        = string
  # 110.x = Rancher 2.15 (annotation ">= 2.15.0-0 < 2.16.0-0").
  default = "110.0.3+up11.0.4"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\+up[0-9]+\\.[0-9]+\\.[0-9]+$", var.rancher_backup_chart_version))
    error_message = "rancher_backup_chart_version must be a pinned chart version such as 110.0.3+up11.0.4."
  }
}

variable "rancher_backup_schedule" {
  description = "Cron schedule of the recurring Rancher backup (operator time zone: UTC)."
  type        = string
  default     = "0 3 * * *"

  validation {
    condition     = length(split(" ", trimspace(var.rancher_backup_schedule))) == 5
    error_message = "rancher_backup_schedule must be a 5-field cron expression."
  }
}

variable "rancher_backup_retention" {
  description = "Number of Rancher backups kept in S3. Older ones are deleted by the operator."
  type        = number
  default     = 10

  validation {
    condition     = var.rancher_backup_retention >= 1 && floor(var.rancher_backup_retention) == var.rancher_backup_retention
    error_message = "rancher_backup_retention must be a positive integer."
  }
}

variable "rancher_chart_repository" {
  description = "Helm repository of the Rancher chart: rancher-stable, or rancher-prime if licensed."
  type        = string
  default     = "https://releases.rancher.com/server-charts/stable"

  validation {
    condition     = startswith(var.rancher_chart_repository, "https://")
    error_message = "rancher_chart_repository must be an https URL."
  }
}

variable "replicas" {
  description = "Rancher replicas. Use the number of server nodes, max. 3."
  type        = number
  default     = 3

  validation {
    condition     = contains([1, 2, 3], var.replicas)
    error_message = "replicas must be 1, 2 or 3."
  }
}

variable "ingress_class_name" {
  description = "Ingress class for Rancher and the Let's Encrypt HTTP-01 solver. Defaults to RKE2's Traefik class; null uses the cluster default class."
  type        = string
  default     = "traefik"
}

variable "kms_key_arn" {
  description = "Optional customer managed KMS key ARN for the admin secret. Null uses the AWS managed key aws/secretsmanager. Reading the kubeconfig secret needs kms:Decrypt on the key used by rke2-cluster."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}
