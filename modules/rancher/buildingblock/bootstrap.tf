# Replaces the single-use bootstrap password with the final admin password and
# sets server-url to the provider api_url (ADR-008).
resource "rancher2_bootstrap" "admin" {
  provider = rancher2.bootstrap

  initial_password = random_password.bootstrap.result
  password         = random_password.admin.result

  depends_on = [data.http.rancher_ping]
}

# Telemetry opt-out.
resource "rancher2_setting" "telemetry_opt" {
  provider = rancher2.admin

  name  = "telemetry-opt"
  value = "out"

  # The only link to Rancher is the rancher2.admin provider config, which
  # OpenTofu does not record as a dependency. Without this, destroy may
  # uninstall Rancher first and this delete then hangs on /ping.
  depends_on = [rancher2_bootstrap.admin]
}
