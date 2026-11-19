# ADR-008: Rancher installation choices

- **Status:** Accepted, 2026-10-16

## Decision

- **cert-manager** is installed first (`helm_release.cert_manager`, namespace `cert-manager`, `crds.enabled=true`, `crds.keep=true`, from the Jetstack repo), pinned with `cert_manager_version`.
- **Rancher**: release `rancher` in namespace `cattle-system`. The namespace is created by `kubernetes_namespace_v1`. The chart comes from `rancher_chart_repository` (rancher-stable by default, rancher-prime if licensed), pinned with `rancher_version`, and depends on cert-manager.
- `replicas` is 1 to 3 (default 3). `antiAffinity` is `required` when `replicas > 1`, otherwise `preferred`.
- `bootstrapPassword` comes from `random_password.bootstrap` and is passed through `set_sensitive`. `rancher2_bootstrap` (provider alias `rancher2.bootstrap`, `bootstrap = true`) replaces it with `random_password.admin` and sets `server-url` to the provider `api_url`.
- Telemetry opt-out uses `rancher2_setting.telemetry_opt` (`telemetry-opt = out`) through a second provider alias `rancher2.admin`, configured with the bootstrap token.
- `tls_source` can be `rancher` (default), `letsEncrypt` (requires `letsencrypt_email`, enforced by a precondition) or `secret`. With `secret`, `tls_certificate_pem` and `tls_private_key_pem` are written to the `tls-rancher-ingress` secret.
- The rancher2 providers set `insecure = var.tls_source != "secret"`. With `rancher` the CA is generated in-cluster during the same run, and with `letsEncrypt` the certificate may not be issued yet. The bootstrap password is single-use. The readiness ping always uses `insecure`.
- The **ingress controller** is set explicitly in the RKE2 config through the `rke2-cluster` input `ingress_controller` (only `traefik`), because the RKE2 default has changed across releases. ingress-nginx was retired upstream in March 2026, RKE2 v1.36 made Traefik the default for new clusters, and v1.37 removes ingress-nginx, so it is no longer accepted. The `rancher` input `ingress_class_name` defaults to `traefik` and is passed to the Rancher ingress and the Let's Encrypt HTTP-01 solver explicitly, instead of relying on the cluster default class.
- The rancher2 provider major version tracks the Rancher minor version (v15 corresponds to Rancher 2.15).

## Consequences

- When `tls_source` is not `secret`, the first admin login over TLS is not verified against a trusted CA.
- A Rancher minor upgrade also requires bumping the rancher2 provider major version.
