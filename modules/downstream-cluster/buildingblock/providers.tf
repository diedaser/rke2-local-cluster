# AWS credentials and region come from the environment (AWS_ACCESS_KEY_ID,
# AWS_SECRET_ACCESS_KEY, AWS_REGION): the runner key, used for the VPC and
# Secrets Manager. Rancher creates the EC2 instances itself with the
# node-driver key (cluster.tf). No provider reads files from the runner.

provider "aws" {
  default_tags {
    tags = local.labels
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Logged in as meshstack-downstream (user-base + clusters-create), never as
# admin (ADR-015). The token comes from auth.tf and lives two hours.
provider "rancher2" {
  api_url   = local.rancher_url
  token_key = local.rancher_token
  insecure  = var.rancher_insecure
  timeout   = "300s"
}
