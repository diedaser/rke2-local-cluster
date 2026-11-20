# IAM user for Rancher's Amazon EC2 node driver (ADR-015).
#
# The node driver runs inside the Rancher pods, which cannot use the node
# instance profile (IMDS hop limit 1, ADR-014), so it needs an access key.
# The key goes into the downstream-cluster definition as encrypted static
# inputs and becomes a rancher2_cloud_credential; meshStack never outputs it.
#
# The policy is the example policy from Rancher's "Creating an Amazon EC2
# Cluster" guide (v2.15), with REGION and ACCOUNT_ID filled in, plus an
# aws:RequestedRegion condition on the actions that take Resource "*".
# Tag-based conditions are intentionally not added until a real provision
# has proven them (ADR-015, "Verify in the first implementation").
# No iam:PassRole: downstream nodes get no instance profile.

locals {
  node_driver_ec2 = "arn:${local.partition}:ec2:${var.region}:${local.account_id}"
}

resource "aws_iam_user" "node_driver" {
  name = "${var.iam_user_name}-node-driver"
  path = "/rke2-node-driver/"
}

data "aws_iam_policy_document" "node_driver" {
  statement {
    sid = "Ec2General"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:Describe*",
      "ec2:ImportKeyPair",
      "ec2:CreateKeyPair",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteKeyPair",
      "ec2:ModifyInstanceMetadataOptions",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.region]
    }
  }

  statement {
    sid     = "RunInstances"
    actions = ["ec2:RunInstances"]
    resources = [
      # Public AMIs (Canonical) have no account in their ARN.
      "arn:${local.partition}:ec2:${var.region}::image/ami-*",
      "${local.node_driver_ec2}:instance/*",
      "${local.node_driver_ec2}:placement-group/*",
      "${local.node_driver_ec2}:volume/*",
      "${local.node_driver_ec2}:subnet/*",
      "${local.node_driver_ec2}:key-pair/*",
      "${local.node_driver_ec2}:network-interface/*",
      "${local.node_driver_ec2}:security-group/*",
    ]
  }

  statement {
    sid = "InstanceLifecycle"
    actions = [
      "ec2:RebootInstances",
      "ec2:TerminateInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
    ]
    resources = ["${local.node_driver_ec2}:instance/*"]
  }

  # Encrypted EBS with a customer managed key (downstream kms_key_arn).
  # The AWS managed key aws/ebs needs no grant.
  dynamic "statement" {
    for_each = var.kms_key_arn == null ? [] : [var.kms_key_arn]
    content {
      sid = "EbsKms"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:DescribeKey",
        "kms:CreateGrant",
      ]
      resources = [statement.value]
    }
  }
}

# Customer managed, not inline: same 2048-byte inline cap as the runner user.
resource "aws_iam_policy" "node_driver" {
  name        = "${var.iam_user_name}-node-driver"
  path        = "/rke2-node-driver/"
  description = "Rancher Amazon EC2 node driver for downstream clusters (ADR-015), restricted to ${var.region}."
  policy      = data.aws_iam_policy_document.node_driver.json
}

resource "aws_iam_user_policy_attachment" "node_driver" {
  user       = aws_iam_user.node_driver.name
  policy_arn = aws_iam_policy.node_driver.arn
}

# Long-lived key: rotate it like the runner key (docs/operations.md).
resource "aws_iam_access_key" "node_driver" {
  user = aws_iam_user.node_driver.name
}
