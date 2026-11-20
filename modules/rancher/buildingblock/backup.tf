# Scheduled Rancher backups to S3 with the rancher-backup operator (ADR-014).
#
# The bucket belongs to the parent rke2-cluster building block (prefix
# rancher/ is ours, etcd/ is RKE2's). The operator runs as a pod and cannot
# use the node instance profile (IMDS hop limit 1), so it gets a dedicated
# IAM user restricted to rancher/. Backups use rancher-resource-set-full,
# which includes secrets, so they are encrypted; the encryption config is
# escrowed in Secrets Manager because a restore into a new cluster needs it.
# Changes here require an ADR update (CONTRIBUTING.md rule 6).

data "aws_region" "current" {}

locals {
  backup_namespace = "cattle-resources-system"
  backup_s3_folder = "rancher"
  backup_s3_region = data.aws_region.current.region
  # Not "rancher-backup-s3": the chart creates a Secret of that name itself
  # (<chart>-s3, its default storage location) and refuses to adopt ours.
  backup_creds_secret      = "rancher-backup-s3-credentials"
  backup_encryption_secret = "rancher-backup-encryption"

  # Created by the rke2-cluster backplane. The runner may only create IAM
  # principals with this boundary attached (ADR-014).
  backup_permissions_boundary = "arn:aws:iam::${var.aws_account_id}:policy/rke2/rke2-backup-boundary"

  # Same format the kube-apiserver uses; rancher-backup reads the key
  # `encryption-provider-config.yaml` from the secret.
  backup_encryption_config = yamlencode({
    apiVersion = "apiserver.config.k8s.io/v1"
    kind       = "EncryptionConfiguration"
    resources = [{
      resources = ["secrets"]
      providers = [{
        aescbc = {
          keys = [{ name = "key1", secret = random_bytes.backup_encryption_key.base64 }]
        }
      }]
    }]
  })
}

# --- AWS: prefix-scoped IAM user ----------------------------------------------

data "aws_iam_policy_document" "rancher_backup" {
  # minio-go (used by the operator) checks the bucket with HEAD bucket, which
  # needs s3:ListBucket without a prefix condition.
  statement {
    sid       = "Bucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${var.backup_bucket_name}"]
  }

  statement {
    sid       = "RancherBackups"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.backup_bucket_name}/${local.backup_s3_folder}/*"]
  }

  # The bucket is encrypted with the rke2-cluster kms_key_arn; set the same
  # key here (docs/meshstack-gui-setup.md).
  dynamic "statement" {
    for_each = var.kms_key_arn == null ? [] : [var.kms_key_arn]
    content {
      sid       = "BackupKms"
      actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
      resources = [statement.value]
    }
  }
}

# Path /rke2-backup/ matches the backplane's IAM scoping.
resource "aws_iam_user" "rancher_backup" {
  name                 = "${local.prefix}-rancher-backup"
  path                 = "/rke2-backup/"
  permissions_boundary = local.backup_permissions_boundary
}

resource "aws_iam_user_policy" "rancher_backup" {
  name   = "rancher-backup-s3"
  user   = aws_iam_user.rancher_backup.name
  policy = data.aws_iam_policy_document.rancher_backup.json
}

# Rotate by tainting this resource and re-running (docs/operations.md).
resource "aws_iam_access_key" "rancher_backup" {
  user = aws_iam_user.rancher_backup.name
}

# --- Encryption key, escrowed for disaster recovery ---------------------------

resource "random_bytes" "backup_encryption_key" {
  length = 32
}

resource "aws_secretsmanager_secret" "backup_encryption" {
  name        = "${local.prefix}-rancher-backup-encryption"
  description = "EncryptionConfiguration of the Rancher backups in s3://${var.backup_bucket_name}/${local.backup_s3_folder}/. Required to restore them (meshStack building block ${var.building_block_uuid})."
  kms_key_id  = var.kms_key_arn

  # Kept after the building block is deleted (default 30 days): the backups
  # in the bucket may outlive it (backup_force_destroy = false) and are
  # useless without this key. 0 where the backups die with the cluster.
  recovery_window_in_days = var.backup_encryption_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "backup_encryption" {
  secret_id     = aws_secretsmanager_secret.backup_encryption.id
  secret_string = local.backup_encryption_config
}

# --- Kubernetes ---------------------------------------------------------------

resource "kubernetes_namespace_v1" "cattle_resources_system" {
  metadata {
    name   = local.backup_namespace
    labels = local.labels
  }

  depends_on = [data.http.api_readyz]

  lifecycle {
    ignore_changes = [metadata[0].labels, metadata[0].annotations]
  }
}

resource "kubernetes_secret_v1" "backup_s3_credentials" {
  metadata {
    name      = local.backup_creds_secret
    namespace = kubernetes_namespace_v1.cattle_resources_system.metadata[0].name
  }

  data = {
    accessKey = aws_iam_access_key.rancher_backup.id
    secretKey = aws_iam_access_key.rancher_backup.secret
  }
}

resource "kubernetes_secret_v1" "backup_encryption" {
  metadata {
    name      = local.backup_encryption_secret
    namespace = kubernetes_namespace_v1.cattle_resources_system.metadata[0].name
  }

  data = {
    "encryption-provider-config.yaml" = local.backup_encryption_config
  }
}

resource "helm_release" "rancher_backup_crd" {
  name       = "rancher-backup-crd"
  namespace  = kubernetes_namespace_v1.cattle_resources_system.metadata[0].name
  repository = "https://charts.rancher.io"
  chart      = "rancher-backup-crd"
  version    = var.rancher_backup_chart_version

  wait    = true
  timeout = 300

  depends_on = [helm_release.rancher]
}

resource "helm_release" "rancher_backup" {
  name       = "rancher-backup"
  namespace  = kubernetes_namespace_v1.cattle_resources_system.metadata[0].name
  repository = "https://charts.rancher.io"
  chart      = "rancher-backup"
  version    = var.rancher_backup_chart_version

  # Default storage location for every Backup without its own.
  values = [yamlencode({
    s3 = {
      enabled                   = true
      credentialSecretName      = kubernetes_secret_v1.backup_s3_credentials.metadata[0].name
      credentialSecretNamespace = kubernetes_secret_v1.backup_s3_credentials.metadata[0].namespace
      bucketName                = var.backup_bucket_name
      folder                    = local.backup_s3_folder
      region                    = local.backup_s3_region
      endpoint                  = "s3.${local.backup_s3_region}.amazonaws.com"
    }
  })]

  wait    = true
  timeout = 600

  depends_on = [helm_release.rancher_backup_crd]
}

# Backup is a CRD from rancher-backup-crd; a local chart applies it in the same
# run (kubernetes_manifest would need the CRD at plan time, ADR-001).
resource "helm_release" "rancher_backup_schedule" {
  name      = "rancher-backup-schedule"
  namespace = kubernetes_namespace_v1.cattle_resources_system.metadata[0].name
  chart     = "${path.module}/charts/rancher-backup-schedule"

  values = [yamlencode({
    name                       = "rancher-scheduled"
    resourceSetName            = "rancher-resource-set-full"
    schedule                   = var.rancher_backup_schedule
    retentionCount             = var.rancher_backup_retention
    encryptionConfigSecretName = kubernetes_secret_v1.backup_encryption.metadata[0].name
  })]

  wait = true

  depends_on = [helm_release.rancher_backup]
}
