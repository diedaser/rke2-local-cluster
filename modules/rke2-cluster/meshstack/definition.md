# meshStack definition: `rke2-cluster`

Summary of what the meshStack building block definition must contain. The
click-by-click setup, including every optional platform input, is in
[docs/meshstack-gui-setup.md](../../../docs/meshstack-gui-setup.md#1-definition-rke2-cluster).
Verify input types and assignment types against the current meshStack docs when
the definition changes (CONTRIBUTING.md rule 13).

| Setting | Value |
|---|---|
| Type | Tenant building block on the AWS platform |
| Implementation | OpenTofu, path `modules/rke2-cluster/buildingblock`, ref = release tag |
| State | meshStack built-in HTTP backend (no `backend` block in code) |
| Dependencies | none |

## Inputs

| Input | Source | Provided as | Encrypted |
|---|---|---|---|
| `AWS_REGION` | Static | Environment | no |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Static | Environment | yes |
| `TF_VAR_state_encryption_passphrase` | Static | Environment | yes |
| `aws_account_id` | Platform Tenant ID (the tenant's AWS account ID) | Variable | no |
| `workspace_identifier` | Workspace Identifier | Variable | no |
| `project_identifier` | Project Identifier | Variable | no |
| `building_block_uuid` | Building Block UUID | Variable | no |
| `cluster_name`, `server_count`, `agent_count`, `server_instance_type`, `agent_instance_type`, `api_allowed_cidrs` | User Input | Variable | no |
| `ami_id`, `rke2_version`, `hardening_profile`, and the optional platform settings in the GUI guide | Static | Variable | no |

## Outputs

None of them is secret (ADR-012).

| Output | Assignment type |
|---|---|
| `kubeconfig_secret_name` | None (consumed by `rancher`) |
| `kubeconfig_secret_arn` | None |
| `api_server_url` | Resource URL |
| `lb_dns_name` | None |
| `vpc_id`, `private_subnet_ids` | None (consumed by `rancher`, passed on to `downstream-cluster`) |
| `summary` | Summary |
