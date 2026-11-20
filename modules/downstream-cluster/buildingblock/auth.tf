# Rancher login as meshstack-downstream (ADR-015).
#
# The `rancher` parent stores the user's login (url, username, password) in
# Secrets Manager. Each run logs in once and uses the resulting token for the
# rancher2 provider. Tokens cannot be minted for another user through the
# provider (rancher2_token is always the caller's own), hence the login.
#
# The token expires after two hours on its own, so the tokens left behind by
# past plans are harmless. ADR-002 is kept: the request is made by the http
# provider, not by a binary on the runner.

data "aws_secretsmanager_secret_version" "rancher_login" {
  secret_id = var.downstream_credentials_secret_name

  lifecycle {
    postcondition {
      condition     = can(jsondecode(self.secret_string).url) && can(jsondecode(self.secret_string).username) && can(jsondecode(self.secret_string).password)
      error_message = "Secret ${var.downstream_credentials_secret_name} does not contain a Rancher login (url, username, password)."
    }
  }
}

locals {
  rancher_login = jsondecode(data.aws_secretsmanager_secret_version.rancher_login.secret_string)
  # The URL is not secret (the rancher building block outputs it as
  # rancher_url); only username and password stay sensitive.
  rancher_url = nonsensitive(trimsuffix(local.rancher_login.url, "/"))

  # Milliseconds, as the login API expects.
  rancher_token_ttl_ms = 2 * 60 * 60 * 1000
}

data "http" "rancher_login" {
  url      = "${local.rancher_url}/v3-public/localProviders/local?action=login"
  method   = "POST"
  insecure = var.rancher_insecure

  request_headers = {
    Content-Type = "application/json"
    Accept       = "application/json"
  }

  request_body = jsonencode({
    username     = local.rancher_login.username
    password     = local.rancher_login.password
    responseType = "json"
    ttl          = local.rancher_token_ttl_ms
    description  = "meshStack downstream-cluster ${var.building_block_uuid}"
  })

  request_timeout_ms = 10000

  # Rancher answers as soon as it is up (ADR-007); a few retries cover a
  # rolling restart of the Rancher pods.
  retry {
    attempts     = 6
    min_delay_ms = 10000
    max_delay_ms = 10000
  }

  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == var.aws_account_id
      error_message = "The AWS credentials belong to account ${data.aws_caller_identity.current.account_id}, but the meshStack tenant is ${var.aws_account_id} (see ADR-013)."
    }
    postcondition {
      condition     = contains([200, 201], self.status_code) && can(jsondecode(self.response_body).token)
      error_message = "Rancher login at ${local.rancher_url} with the downstream user from the secret failed (HTTP ${self.status_code}). Check the user in Rancher and the secret ${var.downstream_credentials_secret_name} (docs/troubleshooting.md)."
    }
  }
}

locals {
  rancher_token = jsondecode(data.http.rancher_login.response_body).token
}
