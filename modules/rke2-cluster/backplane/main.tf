# One-time setup by the platform team. NOT run by meshStack.
#
# Run with administrator credentials for the AWS account the clusters will
# live in (the meshStack tenant's account). Creates the IAM user whose access
# key the meshStack runner uses for both building blocks.

terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.73.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      "managed-by"     = "opentofu"
      "building-block" = "rke2-cluster-backplane"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
}

resource "aws_iam_user" "meshstack_runner" {
  name = var.iam_user_name
  path = "/meshstack/"

  lifecycle {
    precondition {
      condition     = local.account_id == var.account_id
      error_message = "Authenticate to account ${var.account_id} before running the backplane (current: ${local.account_id})."
    }
  }
}

# Least privilege for what the building blocks create, restricted to one
# region. EC2/ELB are not scoped further: resource-level conditions for the
# full VPC/NLB/instance lifecycle are not uniformly supported by AWS.
data "aws_iam_policy_document" "meshstack_runner" {
  statement {
    sid = "Network"
    actions = [
      # Read-only; the provider's refresh calls many Describe APIs.
      "ec2:Describe*",
      "ec2:*Vpc*",
      "ec2:*Subnet*",
      "ec2:*InternetGateway*",
      "ec2:*NatGateway*",
      "ec2:*RouteTable*",
      "ec2:*Route",
      "ec2:*SecurityGroup*",
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress",
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid = "Compute"
    actions = [
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
      "ec2:ModifyInstanceAttribute",
      "ec2:ModifyInstanceMetadataOptions",
      "ec2:ModifyVolume",
      "ec2:CreatePlacementGroup",
      "ec2:DeletePlacementGroup",
      # Server instance profile (etcd snapshots to S3, ADR-014).
      "ec2:AssociateIamInstanceProfile",
      "ec2:ReplaceIamInstanceProfileAssociation",
      "ec2:DisassociateIamInstanceProfile",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid       = "LoadBalancing"
    actions   = ["elasticloadbalancing:*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  # First NLB in an account creates the ELB service-linked role.
  statement {
    sid       = "ElbServiceLinkedRole"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/elasticloadbalancing.amazonaws.com/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }
}

# Second document: IAM inline user policies are capped at 2048 bytes in total,
# so the runner's permissions are customer managed policies (6144 characters
# each), split by concern.
data "aws_iam_policy_document" "meshstack_runner_identity" {
  # Backup bucket per cluster (ADR-014). Bucket names are global, so the
  # scope is the name pattern the rke2-cluster building block uses.
  statement {
    sid     = "BackupBucket"
    actions = ["s3:*"]
    resources = [
      "arn:${local.partition}:s3:::rke2-backup-*",
      "arn:${local.partition}:s3:::rke2-backup-*/*",
    ]
  }

  # Server role and instance profile, under path /rke2/ only.
  statement {
    sid = "ServerRole"
    actions = [
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/rke2/*",
      "arn:${local.partition}:iam::${local.account_id}:instance-profile/rke2/*",
    ]
  }

  # Creating the role or changing its policy requires the backup boundary:
  # without it, PutRolePolicy + PassRole would let the runner mint an
  # instance with any permission (privilege escalation).
  statement {
    sid       = "ServerRoleBounded"
    actions   = ["iam:CreateRole", "iam:PutRolePolicy"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/rke2/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.backup_boundary.arn]
    }
  }

  # Without PassRole scoping, the runner could hand any role to an instance.
  statement {
    sid       = "PassServerRole"
    actions   = ["iam:PassRole"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:role/rke2/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  # rancher-backup operator user (rancher building block), under path
  # /rke2-backup/ only. The user's own policy is limited to rancher/ in the
  # backup bucket; the runner cannot create users elsewhere.
  statement {
    sid = "BackupUser"
    actions = [
      "iam:DeleteUser",
      "iam:GetUser",
      "iam:TagUser",
      "iam:UntagUser",
      "iam:ListGroupsForUser",
      "iam:ListUserPolicies",
      "iam:ListAttachedUserPolicies",
      "iam:GetUserPolicy",
      "iam:DeleteUserPolicy",
      "iam:CreateAccessKey",
      "iam:DeleteAccessKey",
      "iam:ListAccessKeys",
    ]
    resources = ["arn:${local.partition}:iam::${local.account_id}:user/rke2-backup/*"]
  }

  statement {
    sid       = "BackupUserBounded"
    actions   = ["iam:CreateUser", "iam:PutUserPolicy"]
    resources = ["arn:${local.partition}:iam::${local.account_id}:user/rke2-backup/*"]
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.backup_boundary.arn]
    }
  }

  statement {
    sid = "Secrets"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
      "secretsmanager:GetResourcePolicy",
    ]
    resources = ["arn:${local.partition}:secretsmanager:${var.region}:${local.account_id}:secret:*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn == null ? [] : [var.kms_key_arn]
    content {
      sid = "CustomerManagedKey"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant",
      ]
      resources = [statement.value]
    }
  }
}

# Permissions boundary for every IAM principal the building blocks create
# (server role, rancher-backup user). Whatever inline policy the runner
# writes, the effective permissions never exceed the backup bucket (and the
# KMS key). The building blocks reference it by this fixed ARN.
data "aws_iam_policy_document" "backup_boundary" {
  statement {
    sid     = "BackupBucket"
    actions = ["s3:ListBucket", "s3:GetBucketLocation", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = [
      "arn:${local.partition}:s3:::rke2-backup-*",
      "arn:${local.partition}:s3:::rke2-backup-*/*",
    ]
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

resource "aws_iam_policy" "backup_boundary" {
  name        = "rke2-backup-boundary"
  path        = "/rke2/"
  description = "Permissions boundary for IAM principals created by the rke2-cluster and rancher building blocks (ADR-014)."
  policy      = data.aws_iam_policy_document.backup_boundary.json
}

locals {
  runner_policies = {
    infrastructure = {
      description = "VPC, EC2 and NLB for the rke2-cluster building block, restricted to one region."
      json        = data.aws_iam_policy_document.meshstack_runner.json
    }
    identity = {
      description = "Backup bucket, bounded IAM principals, Secrets Manager and KMS for the rke2-cluster and rancher building blocks (ADR-012, ADR-014)."
      json        = data.aws_iam_policy_document.meshstack_runner_identity.json
    }
  }
}

resource "aws_iam_policy" "meshstack_runner" {
  for_each = local.runner_policies

  name        = "${var.iam_user_name}-${each.key}"
  path        = "/meshstack/"
  description = each.value.description
  policy      = each.value.json
}

resource "aws_iam_user_policy_attachment" "meshstack_runner" {
  for_each = aws_iam_policy.meshstack_runner

  user       = aws_iam_user.meshstack_runner.name
  policy_arn = each.value.arn
}

# Long-lived key: rotate it regularly (docs/operations.md).
resource "aws_iam_access_key" "meshstack_runner" {
  user = aws_iam_user.meshstack_runner.name
}
