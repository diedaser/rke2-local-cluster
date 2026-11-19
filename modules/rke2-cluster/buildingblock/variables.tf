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

variable "aws_account_id" {
  description = "AWS account ID of the meshStack tenant (source: Platform Tenant ID). Must match the account of the runner credentials."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12 digit AWS account ID."
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

variable "server_instance_type" {
  description = "EC2 instance type for server nodes. Rancher management clusters need at least 4 vCPU and 16 GiB RAM. Its architecture must match ami_id."
  type        = string
  default     = "m7i.xlarge"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.server_instance_type))
    error_message = "server_instance_type must be an EC2 instance type such as m7i.xlarge."
  }
}

variable "agent_instance_type" {
  description = "EC2 instance type for agent nodes. Defaults to server_instance_type."
  type        = string
  default     = null

  validation {
    condition     = var.agent_instance_type == null || can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.agent_instance_type))
    error_message = "agent_instance_type must be an EC2 instance type such as m7i.xlarge."
  }
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API (6443) on the client-facing load balancer."
  type        = list(string)

  validation {
    condition     = alltrue([for c in var.api_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "api_allowed_cidrs must contain valid CIDRs, for example 10.0.0.0/8."
  }
}

# --- Platform-controlled inputs ------------------------------------------------

variable "ami_id" {
  description = "AMI ID of Ubuntu 24.04 LTS for the region (pinned, ADR-009). Canonical publishes it in SSM: /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id."
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "ami_id must be an AMI ID such as ami-0123456789abcdef0."
  }
}

variable "rke2_version" {
  description = "RKE2 version (INSTALL_RKE2_VERSION). Must be supported by the Rancher version installed on top (support matrix)."
  type        = string
  # Rancher v2.15.2 support matrix: local/hosting cluster RKE2 v1.34 - v1.36.
  # v1.36.6 = RKE2 stable channel (2026-11-05).
  default = "v1.36.6+rke2r1"

  validation {
    condition     = can(regex("^v1\\.[0-9]+\\.[0-9]+\\+rke2r[0-9]+$", var.rke2_version))
    error_message = "rke2_version must be a pinned RKE2 release such as v1.36.6+rke2r1, never 'latest' or a channel."
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
  description = "CIDRs allowed to reach ingress (80/443, Rancher UI) on the client-facing load balancer."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = alltrue([for c in var.ingress_allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "ingress_allowed_cidrs must contain valid CIDRs."
  }
}

variable "public_load_balancer" {
  description = "Create an internet-facing NLB for clients (6443, 80, 443). Disable only if the runner and users reach the VPC privately (VPN, peering, Transit Gateway)."
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR of the cluster VPC, /16 to /24. Split into 8 subnets (4 private, 4 public). Must not overlap the RKE2 pod (10.42.0.0/16) and service (10.43.0.0/16) CIDRs."
  type        = string
  default     = "10.100.0.0/16"

  validation {
    # Integer range check against 10.42.0.0 - 10.43.255.255.
    condition = can(cidrhost(var.vpc_cidr, 0)) && try(
      tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 24 && alltrue([
        for o in [[for x in split(".", cidrhost(var.vpc_cidr, 0)) : tonumber(x)]] :
        o[0] * 16777216 + o[1] * 65536 + o[2] * 256 + o[3] > 170655743 ||
        o[0] * 16777216 + o[1] * 65536 + o[2] * 256 + o[3] + pow(2, 32 - tonumber(split("/", var.vpc_cidr)[1])) <= 170524672
      ]),
      false,
    )
    error_message = "vpc_cidr must be a valid /16 to /24 CIDR outside 10.42.0.0/16 and 10.43.0.0/16."
  }
}

variable "api_extra_sans" {
  description = "Additional DNS names or IPs for the API server certificate (for example a DNS name pointing at the NLB). The NLB DNS names are always included."
  type        = list(string)
  default     = []
}

variable "ssh_key_name" {
  description = "Optional EC2 key pair name for break-glass SSH (from a bastion in the VPC). Never used by OpenTofu (ADR-002)."
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

variable "root_volume_size_gb" {
  description = "gp3 root volume size per node in GiB."
  type        = number
  default     = 100

  validation {
    condition     = var.root_volume_size_gb >= 40 && var.root_volume_size_gb <= 16384
    error_message = "root_volume_size_gb must be between 40 and 16384."
  }
}

variable "root_volume_iops" {
  description = "Provisioned IOPS of the gp3 root volumes. etcd is latency sensitive; 3000 is the gp3 baseline."
  type        = number
  default     = 3000

  validation {
    condition     = var.root_volume_iops >= 3000 && var.root_volume_iops <= 16000
    error_message = "root_volume_iops must be between 3000 and 16000."
  }
}

variable "kms_key_arn" {
  description = "Optional customer managed KMS key ARN for EBS volumes and the kubeconfig secret. Null uses the AWS managed keys (aws/ebs, aws/secretsmanager)."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN."
  }
}

variable "availability_zones" {
  description = "Optional availability zones (max. 4). Empty uses the first 3 zones of the region (sorted). Nodes are spread round-robin."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.availability_zones) <= 4 && length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "availability_zones must contain at most 4 distinct zones."
  }
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
