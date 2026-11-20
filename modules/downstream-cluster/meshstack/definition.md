# meshStack definition: `downstream-cluster`

Summary of what the meshStack building block definition must contain. The
click-by-click setup is in
[docs/meshstack-gui-setup.md](../../../docs/meshstack-gui-setup.md#3-definition-downstream-cluster).
Verify input types and assignment types against the current meshStack docs when
the definition changes (CONTRIBUTING.md rule 13).

| Setting | Value |
|---|---|
| Type | Tenant building block on the AWS platform |
| Implementation | OpenTofu, path `modules/downstream-cluster/buildingblock`, ref = release tag |
| State | meshStack built-in HTTP backend (no `backend` block in code) |
| Dependencies | `rancher` (enables the Parent Building Block Output source); same tenant |
| Only apply once per tenant | Off (several downstream clusters per tenant and parent) |

## Inputs

| Input | Source | Provided as | Encrypted |
|---|---|---|---|
| `AWS_REGION` | Static | Environment | no |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Static (runner key) | Environment | yes |
| `TF_VAR_state_encryption_passphrase` | Static (its own passphrase) | Environment | yes |
| `node_driver_access_key_id`, `node_driver_secret_access_key` | Static (backplane node-driver key) | Variable | yes |
| `aws_account_id` | Platform Tenant ID | Variable | no |
| `workspace_identifier`, `project_identifier`, `building_block_uuid` | meshStack identifiers | Variable | no |
| `downstream_credentials_secret_name` | Parent Building Block Output | Variable | no |
| `cluster_name`, `control_plane_count`, `worker_count`, `control_plane_instance_type`, `worker_instance_type` | User Input | Variable | no |
| `ami_id`, `kubernetes_version`, `rancher_insecure`, `vpc_cidr`, `availability_zones`, `kms_key_arn`, `root_volume_size_gb` | Static | Variable | no |

## Outputs

None of them is secret (ADR-012). There is no kubeconfig output.

| Output | Assignment type |
|---|---|
| `cluster_name` | None |
| `rancher_cluster_id` | None |
| `rancher_cluster_url` | Resource URL |
| `nat_public_ip` | None |
| `summary` | Summary |
