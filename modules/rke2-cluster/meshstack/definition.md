# meshStack definition: `rke2-cluster`

Summary of what the meshStack building block definition must contain. The
click-by-click setup, including every optional platform input, is in
[docs/meshstack-gui-setup.md](../../../docs/meshstack-gui-setup.md#1-definition-rke2-cluster).
Verify input types and assignment types against the current meshStack docs when
the definition changes (CONTRIBUTING.md rule 13).

| Setting | Value |
|---|---|
| Type | Tenant building block on the OpenStack platform |
| Implementation | OpenTofu, path `modules/rke2-cluster/buildingblock`, ref = release tag |
| State | meshStack built-in HTTP backend (no `backend` block in code) |
| Dependencies | none |

## Inputs

| Input | Source | Provided as | Encrypted |
|---|---|---|---|
| `OS_AUTH_URL`, `OS_REGION_NAME`, `OS_AUTH_TYPE` | Static | Environment | no |
| `OS_APPLICATION_CREDENTIAL_ID`, `OS_APPLICATION_CREDENTIAL_SECRET` | Static | Environment | yes |
| `TF_VAR_state_encryption_passphrase` | Static | Environment | yes |
| `openstack_project_id` | Platform Tenant ID | Variable | no |
| `workspace_identifier` | Workspace Identifier | Variable | no |
| `project_identifier` | Project Identifier | Variable | no |
| `building_block_uuid` | Building Block UUID | Variable | no |
| `cluster_name`, `server_count`, `agent_count`, `server_flavor`, `agent_flavor`, `api_allowed_cidrs` | User Input | Variable | no |
| `image_name`, `external_network_name`, `rke2_version`, `hardening_profile`, and the optional platform settings in the GUI guide | Static | Variable | no |

## Outputs

None of them is secret (ADR-012).

| Output | Assignment type |
|---|---|
| `kubeconfig_secret_name` | None (consumed by `rancher`) |
| `kubeconfig_secret_ref` | None |
| `api_server_url` | Resource URL |
| `lb_ip` | None |
| `summary` | Summary |
