resource "random_password" "rke2_token" {
  length  = 48
  special = false
}

locals {
  # The first server uses the bare secret. Joining nodes use the full token
  # format, which pins the cluster CA: K10<sha256 of server-ca.crt>::server:<secret>.
  # cloud-init writes server-ca.crt byte-identical to cert_pem (base64 encoded
  # write_files), so the hash matches what RKE2 serves on /cacerts.
  rke2_token_secret = random_password.rke2_token.result
  rke2_join_token   = "K10${sha256(tls_self_signed_cert.ca["server-ca"].cert_pem)}::server:${random_password.rke2_token.result}"
}
