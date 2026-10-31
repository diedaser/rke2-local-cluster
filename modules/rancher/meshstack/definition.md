# meshStack definition: `rancher`

Summary of what the meshStack building block definition must contain. The
click-by-click setup is in
[docs/meshstack-gui-setup.md](../../../docs/meshstack-gui-setup.md#2-definition-rancher).
Verify input types and assignment types against the current meshStack docs when
the definition changes (CONTRIBUTING.md rule 13).

| Setting | Value |
|---|---|
| Type | Tenant building block on the OpenStack platform |
| Implementation | OpenTofu, path `modules/rancher/buildingblock`, ref = release tag |
| State | meshStack built-in HTTP backend (no `backend` block in code) |
| Dependencies | `rke2-cluster` (enables the Parent Building Block Output source) |

## Inputs

| Input | Source | Provided as | Encrypted |
|---|---|---|---|
| `OS_AUTH_URL`, `OS_REGION_NAME`, `OS_AUTH_TYPE` | Static | Environment | no |
| `OS_APPLICATION_CREDENTIAL_ID`, `OS_APPLICATION_CREDENTIAL_SECRET` | Static | Environment | yes |
| `TF_VAR_state_encryption_passphrase` | Static (its own passphrase) | Environment | yes |
| `openstack_project_id` | Platform Tenant ID | Variable | no |
| `workspace_identifier`, `project_identifier`, `building_block_uuid` | meshStack identifiers | Variable | no |
| `kubeconfig_secret_name` | Parent Building Block Output | Variable | no |
| `api_server_url` | Parent Building Block Output | Variable | no |
| `rancher_hostname`, `tls_source` | User Input | Variable | no |
| `letsencrypt_email` | User Input, condition `tls_source == "letsEncrypt"` | Variable | no |
| `tls_certificate_pem`, `tls_private_key_pem` | User Input, condition `tls_source == "secret"` | Variable | yes |
| `rancher_version`, `cert_manager_version`, `rancher_chart_repository`, `replicas`, `ingress_class_name` | Static (optional) | Variable | no |

## Outputs

None of them is secret (ADR-012).

| Output | Assignment type |
|---|---|
| `rancher_url` | Resource URL |
| `admin_secret_ref` | None |
| `admin_secret_name` | None |
| `summary` | Summary |
