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
  description = "meshStack building block UUID (source: Building Block UUID). Makes resource names unique."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{8,}$", var.building_block_uuid))
    error_message = "building_block_uuid must be a UUID."
  }
}

variable "openstack_project_id" {
  description = "OpenStack project ID of the meshStack tenant (source: Platform Tenant ID). Must match the project of the runner credentials."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.openstack_project_id))
    error_message = "openstack_project_id must be a 32 character hex OpenStack project ID."
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

variable "cluster_name" {
  description = "Name of the cluster. Lowercase letters, digits and dashes, 3-31 characters, starting with a letter."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.cluster_name))
    error_message = "cluster_name must match ^[a-z][a-z0-9-]{2,30}$."
  }
}

variable "server_count" {
  description = "Number of server nodes (control plane + etcd): 1 (dev), 3 or 5. A string because meshStack Single Select inputs arrive as strings; numbers are converted automatically."
  type        = string
  default     = "3"

  validation {
    condition     = contains(["1", "3", "5"], var.server_count)
    error_message = "server_count must be 1, 3 or 5 (etcd needs an odd number of members)."
  }
}

variable "agent_count" {
  description = "Number of agent (worker) nodes. 0 is the Rancher best practice for a dedicated management cluster."
  type        = number
  default     = 0

  validation {
    condition     = var.agent_count >= 0 && var.agent_count <= 50 && floor(var.agent_count) == var.agent_count
    error_message = "agent_count must be an integer between 0 and 50."
  }
}

variable "server_flavor" {
  description = "Nova flavor for server nodes. Rancher management clusters need at least 4 vCPU and 16 GiB RAM."
  type        = string

  validation {
    condition     = length(trimspace(var.server_flavor)) > 0
    error_message = "server_flavor must not be empty."
  }
}

variable "agent_flavor" {
  description = "Nova flavor for agent nodes. Defaults to server_flavor."
  type        = string
  default     = null
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API (6443) on the load balancer."
  type        = list(string)

  validation {
    condition     = alltrue([for c in var.api_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "api_allowed_cidrs must contain valid CIDRs, for example 10.0.0.0/8."
  }
}

# --- Platform-controlled inputs ------------------------------------------------

variable "image_name" {
  description = "Glance image name (Ubuntu 24.04 LTS or SLE Micro with cloud-init)."
  type        = string

  validation {
    condition     = length(trimspace(var.image_name)) > 0
    error_message = "image_name must not be empty."
  }
}

variable "rke2_version" {
  description = "RKE2 version (INSTALL_RKE2_VERSION). Must be supported by the Rancher version installed on top (support matrix)."
  type        = string
  # Rancher v2.15.2 support matrix: local/hosting cluster RKE2 v1.34 - v1.36.
  default = "v1.35.9+rke2r1"

  validation {
    condition     = can(regex("^v1\\.[0-9]+\\.[0-9]+\\+rke2r[0-9]+$", var.rke2_version))
    error_message = "rke2_version must be a pinned RKE2 release such as v1.35.9+rke2r1, never 'latest' or a channel."
  }
}

variable "hardening_profile" {
  description = "RKE2 hardening profile: `cis` (production) or `none` (dev)."
  type        = string
  default     = "cis"

  validation {
    condition     = contains(["cis", "none"], var.hardening_profile)
    error_message = "hardening_profile must be 'cis' or 'none'."
  }
}

variable "ingress_controller" {
  description = "Ingress controller deployed by RKE2. Set explicitly because the RKE2 default changes across releases (ADR-008)."
  type        = string
  default     = "ingress-nginx"

  validation {
    condition     = contains(["ingress-nginx", "traefik"], var.ingress_controller)
    error_message = "ingress_controller must be 'ingress-nginx' or 'traefik'."
  }
}

variable "admin_cert_validity_hours" {
  description = "Validity of the admin client certificate in hours. Re-applying within the last quarter of the validity (max. 30 days) renews it."
  type        = number
  default     = 8760

  validation {
    condition     = var.admin_cert_validity_hours >= 24 && var.admin_cert_validity_hours <= 87600
    error_message = "admin_cert_validity_hours must be between 24 and 87600."
  }
}

variable "runner_egress_cidrs" {
  description = "Egress CIDRs of the meshStack building block runner. Appended to the API and ingress allow lists so the runner can reach 6443 and 443."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.runner_egress_cidrs : can(cidrhost(c, 0))])
    error_message = "runner_egress_cidrs must contain valid CIDRs."
  }
}

variable "ingress_allowed_cidrs" {
  description = "CIDRs allowed to reach ingress (80/443, Rancher UI) on the load balancer."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.ingress_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "ingress_allowed_cidrs must contain valid CIDRs."
  }
}

variable "external_network_name" {
  description = "Name of the external (provider) network used for the router gateway and the load balancer floating IP."
  type        = string

  validation {
    condition     = length(trimspace(var.external_network_name)) > 0
    error_message = "external_network_name must not be empty."
  }
}

variable "assign_floating_ip" {
  description = "Assign a floating IP to the load balancer VIP. Disable only if the runner and users reach the private subnet directly."
  type        = bool
  default     = true
}

variable "subnet_cidr" {
  description = "CIDR of the cluster subnet. Must not overlap the RKE2 pod (10.42.0.0/16) and service (10.43.0.0/16) CIDRs."
  type        = string
  default     = "192.168.42.0/24"

  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0)) && !contains(["10.42.", "10.43."], substr(var.subnet_cidr, 0, 6))
    error_message = "subnet_cidr must be a valid CIDR outside 10.42.0.0/16 and 10.43.0.0/16."
  }
}

variable "dns_nameservers" {
  description = "DNS servers for the cluster subnet. Empty uses the Neutron default."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for ip in var.dns_nameservers : can(cidrhost("${ip}/32", 0))])
    error_message = "dns_nameservers must contain IPv4 addresses."
  }
}

variable "api_extra_sans" {
  description = "Additional DNS names or IPs for the API server certificate (for example a DNS name pointing at the LB)."
  type        = list(string)
  default     = []
}

variable "ssh_key_pair" {
  description = "Optional Nova key pair for break-glass SSH. Never used by OpenTofu (ADR-002)."
  type        = string
  default     = null
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs (bastion/admin) allowed to SSH to the nodes. Empty means no SSH rule."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.ssh_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "ssh_allowed_cidrs must contain valid CIDRs."
  }
}

variable "boot_volume_size_gb" {
  description = "Boot volume size per node in GiB."
  type        = number
  default     = 100

  validation {
    condition     = var.boot_volume_size_gb >= 40
    error_message = "boot_volume_size_gb must be at least 40."
  }
}

variable "boot_volume_type" {
  description = "Optional Cinder volume type for boot volumes. Use a low-latency SSD type, etcd is latency sensitive."
  type        = string
  default     = null
}

variable "availability_zones" {
  description = "Optional availability zones, assigned to nodes round-robin."
  type        = list(string)
  default     = []
}

variable "lb_provider" {
  description = "Optional Octavia provider (for example `amphora` or `ovn`). Null uses the cloud default."
  type        = string
  default     = null
}

variable "etcd_snapshot_schedule_cron" {
  description = "Cron schedule for local etcd snapshots."
  type        = string
  default     = "0 */6 * * *"

  validation {
    condition     = length(split(" ", trimspace(var.etcd_snapshot_schedule_cron))) == 5
    error_message = "etcd_snapshot_schedule_cron must be a 5-field cron expression."
  }
}

variable "etcd_snapshot_retention" {
  description = "Number of etcd snapshots to keep per server."
  type        = number
  default     = 28

  validation {
    condition     = var.etcd_snapshot_retention >= 1
    error_message = "etcd_snapshot_retention must be at least 1."
  }
}

variable "rke2_install_script_url" {
  description = "URL of the RKE2 install script fetched by the nodes (not the runner). Override for a mirror."
  type        = string
  default     = "https://get.rke2.io"

  validation {
    condition     = startswith(var.rke2_install_script_url, "https://")
    error_message = "rke2_install_script_url must be an https URL."
  }
}
