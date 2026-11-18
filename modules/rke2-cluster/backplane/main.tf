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

resource "aws_iam_user_policy" "meshstack_runner" {
  name   = "rke2-rancher-building-blocks"
  user   = aws_iam_user.meshstack_runner.name
  policy = data.aws_iam_policy_document.meshstack_runner.json
}

# Long-lived key: rotate it regularly (docs/operations.md).
resource "aws_iam_access_key" "meshstack_runner" {
  user = aws_iam_user.meshstack_runner.name
}
