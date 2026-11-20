# Off-cluster backups (ADR-014).
#
# One private bucket per cluster holds two prefixes:
#   etcd/     RKE2 etcd snapshots, written by the server nodes through their
#             instance profile (the rke2-server process reads IMDS on the
#             host; pods cannot, hop limit 1).
#   rancher/  rancher-backup operator archives, written by the `rancher`
#             building block with its own prefix-scoped IAM user.
# Retention is enforced by RKE2 (etcd_snapshot_retention) and the
# rancher-backup operator (retentionCount), not by an S3 lifecycle rule.

locals {
  # Global bucket namespace: short_id + account ID keeps it unique. The
  # backplane IAM policy scopes S3 permissions to "rke2-backup-*".
  backup_bucket_name = "rke2-backup-${local.short_id}-${var.aws_account_id}"
  etcd_s3_folder     = "etcd"

  # Created by the backplane. The runner may only create IAM principals with
  # this boundary attached (privilege-escalation guard, ADR-014).
  backup_permissions_boundary = "arn:aws:iam::${var.aws_account_id}:policy/rke2/rke2-backup-boundary"
}

resource "aws_s3_bucket" "backup" {
  bucket = local.backup_bucket_name

  # false keeps the backups when the building block is deleted, so a
  # cluster can be restored after an accidental delete. The destroy then
  # fails until the bucket is emptied by hand (docs/operations.md).
  force_destroy = var.backup_force_destroy

  tags = { Name = local.backup_bucket_name }
}

resource "aws_s3_bucket_ownership_controls" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket                  = aws_s3_bucket.backup.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null
  }
}

# Versioning is off on purpose: retention deletes must actually free space.
# Abort leftovers of interrupted multipart uploads.
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

data "aws_iam_policy_document" "backup_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.backup.arn, "${aws_s3_bucket.backup.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "backup" {
  bucket = aws_s3_bucket.backup.id
  policy = data.aws_iam_policy_document.backup_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.backup]
}

# --- Server node role: etcd snapshots only ------------------------------------

data "aws_iam_policy_document" "server_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "server_etcd_s3" {
  # Not prefix-conditioned: RKE2's S3 client (minio-go) checks the bucket with
  # HEAD bucket, which needs s3:ListBucket without a prefix. Listing reveals
  # object names under rancher/ only, never their content.
  statement {
    sid       = "Bucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.backup.arn]
  }

  statement {
    sid       = "EtcdSnapshots"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.backup.arn}/${local.etcd_s3_folder}/*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn == null ? [] : [var.kms_key_arn]
    content {
      sid       = "BackupKms"
      actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
      resources = [statement.value]
    }
  }
}

# Path /rke2/ matches the backplane's IAM scoping.
resource "aws_iam_role" "server" {
  name                 = "${local.prefix}-server"
  path                 = "/rke2/"
  assume_role_policy   = data.aws_iam_policy_document.server_assume.json
  permissions_boundary = local.backup_permissions_boundary
}

resource "aws_iam_role_policy" "server_etcd_s3" {
  name   = "etcd-snapshots-s3"
  role   = aws_iam_role.server.id
  policy = data.aws_iam_policy_document.server_etcd_s3.json
}

resource "aws_iam_instance_profile" "server" {
  name = "${local.prefix}-server"
  path = "/rke2/"
  role = aws_iam_role.server.name
}
