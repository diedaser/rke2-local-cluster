# Least-privilege Rancher identity for the downstream-cluster building block
# (ADR-015). Not the admin token.
#
# The secret holds credentials, not an API token: rancher2_token always mints
# for the provider's own (admin) user, and Rancher lets users create tokens
# only for themselves. downstream-cluster logs in with these credentials per
# run and gets a short-lived token.
#
# Rancher assigns its "new user default" roles only to external-auth
# principals on first login (usermanager.EnsureUser), never to local users
# created through the API. The two bindings below are therefore the user's
# complete permissions:
#   user-base        log in, manage its own tokens and preferences
#   clusters-create  create provisioning clusters, machine configs, and cloud
#                    credential secrets (cattle-global-data, fleet-default).
#                    As creator it becomes owner of the clusters it creates.
# Changes here require an ADR update (CONTRIBUTING.md rule 6).

locals {
  downstream_username = "meshstack-downstream"
}

resource "random_password" "downstream" {
  length  = 32
  special = false
}

resource "rancher2_user" "downstream" {
  provider = rancher2.admin

  username = local.downstream_username
  name     = "meshStack downstream-cluster building block"
  password = random_password.downstream.result
  enabled  = true

  # The only link to Rancher is the provider config (see telemetry_opt).
  depends_on = [rancher2_bootstrap.admin]

  lifecycle {
    # username and password are ForceNew. Replacing the user changes its ID,
    # and the downstream clusters it created would lose their owner. Rotate
    # the password in Rancher and in the secret instead (docs/operations.md).
    ignore_changes = [password]
  }
}

resource "rancher2_global_role_binding" "downstream" {
  for_each = toset(["user-base", "clusters-create"])
  provider = rancher2.admin

  name           = "meshstack-downstream-${each.key}"
  global_role_id = each.key
  user_id        = rancher2_user.downstream.id
}

resource "aws_secretsmanager_secret" "downstream" {
  name        = "${local.prefix}-rancher-downstream"
  description = "Rancher login of the downstream-cluster building block for ${local.rancher_url} (meshStack building block ${var.building_block_uuid})."
  kms_key_id  = var.kms_key_arn

  # Worthless once Rancher is gone; immediate deletion allows re-creation
  # under the same name.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "downstream" {
  secret_id = aws_secretsmanager_secret.downstream.id
  secret_string = jsonencode({
    url      = local.rancher_url
    username = rancher2_user.downstream.username
    password = random_password.downstream.result
  })

  # Publish only credentials that work: the user exists and has its roles.
  depends_on = [rancher2_global_role_binding.downstream]
}
