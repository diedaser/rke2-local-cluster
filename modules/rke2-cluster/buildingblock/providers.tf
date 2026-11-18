# Credentials and region come exclusively from the environment set by the
# meshStack definition (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION).
# Every resource carries the meshStack labels as tags (ADR-010).
provider "aws" {
  default_tags {
    tags = local.labels
  }
}

# The account the credentials belong to. Checked against the meshStack tenant
# (aws_account_id) before anything is created, see network.tf (ADR-013).
data "aws_caller_identity" "current" {}
