# meshStack definition: `rancher`

Summary of what the meshStack building block definition must contain. The
click-by-click setup is in
[docs/meshstack-gui-setup.md](../../../docs/meshstack-gui-setup.md#2-definition-rancher).
Verify input types and assignment types against the current meshStack docs when
the definition changes (CONTRIBUTING.md rule 13).

| Setting | Value |
|---|---|
| Type | Tenant building block on the AWS platform |
| Implementation | OpenTofu, path `modules/rancher/buildingblock`, ref = release tag |
| State | meshStack built-in HTTP backend (no `backend` block in code) |
| Dependencies | `rke2-cluster` (enables the Parent Building Block Output source) |

## Inputs

| Input | Source | Provided as | Encrypted |
|---|---|---|---|
| `AWS_REGION` | Static | Environment | no |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Static | Environment | yes |
| `TF_VAR_state_encryption_passphrase` | Static (its own passphrase) | Environment | yes |
| `aws_account_id` | Platform Tenant ID (the tenant's AWS account ID) | Variable | no |
| `workspace_identifier`, `project_identifier`, `building_block_uuid` | meshStack identifiers | Variable | no |
| `kubeconfig_secret_name` | Parent Building Block Output | Variable | no |
| `api_server_url` | Parent Building Block Output | Variable | no |
| `rancher_hostname`, `tls_source` | User Input | Variable | no |
| `letsencrypt_email` | User Input, condition `tls_source == "letsEncrypt"` | Variable | no |
| `tls_certificate_pem`, `tls_private_key_pem` | User Input, condition `tls_source == "secret"` | Variable | yes |
| `rancher_version`, `cert_manager_version`, `rancher_chart_repository`, `replicas`, `ingress_class_name`, `kms_key_arn` | Static (optional) | Variable | no |

## Outputs

None of them is secret (ADR-012).

| Output | Assignment type |
|---|---|
| `rancher_url` | Resource URL |
| `admin_secret_name` | None |
| `admin_secret_arn` | None |
| `summary` | Summary |
