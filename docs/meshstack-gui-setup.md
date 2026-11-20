# Creating the Building Block Definitions in the meshStack GUI

This guide walks through creating the two building block definitions, `rke2-cluster` and `rancher`, in meshPanel. Create them **in this order**, because `rancher` depends on `rke2-cluster`.

> Menu labels follow the meshStack docs as of October 2026. If your meshStack version shows a field under a slightly different name, the meaning is the same. Fields this guide doesn't mention can stay at their defaults.

---

## 0. Prerequisites

Do these once, before opening the wizard.

1. **Run the backplane** (platform team, outside meshStack):
   ```bash
   cd modules/rke2-cluster/backplane
   tofu init && tofu apply
   tofu output -json   # aws_region, aws_account_id, aws_access_key_id, aws_secret_access_key
   ```
   Keep the output at hand, but don't save it to a file in the repo. Re-run `tofu apply` here whenever the backplane changes (for example the S3/IAM permissions and the `rke2-backup-boundary` policy for backups, ADR-014) **before** releasing definition versions that need them. The backplane needs its own state passphrase in `TF_VAR_state_encryption_passphrase` and runs with administrator credentials for the tenant's AWS account (`-var account_id=... -var region=...`).

2. **Create a Git deploy key** (no passphrase):
   ```bash
   ssh-keygen -t ed25519 -C "meshstack-bb-rke2" -f ./meshstack_deploy_key -N ""
   ```
   - Add `meshstack_deploy_key.pub` as a **read-only deploy key** on the Git repo.
   - Keep the private key `meshstack_deploy_key` for upload in step 1.3.
   - Collect the host keys of your Git server: `ssh-keyscan <git-host>`.

3. **Tag a release** of this repo (for example `v1.0.0`). Definitions must point at a tag or commit, never at a moving branch.

4. **Check runner reachability.** The runner must reach the AWS APIs, and later the cluster API (6443) and Rancher (443) through the client-facing NLB. With `public_load_balancer = false` the NLB is internal to the VPC; then register a **self-hosted building block runner** first, and select it in the definitions.

5. **Generate the state encryption passphrases** (at least 16 characters each, one per definition, kept in your password manager):
   ```bash
   openssl rand -base64 32
   ```
   The same passphrase must stay on the definition for good. If it changes, existing states can no longer be read. OpenTofu reads it from the environment variable `TF_VAR_state_encryption_passphrase` (OpenTofu can only read variables through the `TF_VAR_` prefix, see ADR-004).

6. **Check the account scope.** The IAM access key belongs to one AWS account and its policy is restricted to one region. Both building blocks refuse to run when the meshStack tenant's account (Platform Tenant ID) differs (ADR-013). Offer the definitions only on tenants in that account. Verify in the meshStack docs that the AWS platform's Platform Tenant ID is the 12-digit account ID (CONTRIBUTING.md rule 13).

7. **Look up the AMI.** Pin the current Canonical Ubuntu 24.04 amd64 AMI for the region:
   ```bash
   aws ssm get-parameter --region <region> \
     --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
     --query Parameter.Value --output text
   ```

---

## 1. Definition `rke2-cluster`

**Open the wizard:** go to **Admin Area → Marketplace → Building Block Definitions → Create new Definition**. In the Platform Builder view the path is **Building Blocks → Definitions → Create new Definition**.

### 1.1 General

| Field | Value |
|---|---|
| Definition name | `RKE2 Cluster (Rancher management)` |
| Description | `Provisions a highly available RKE2 cluster (3 servers, CIS profile) on AWS EC2 (Ubuntu 24.04), intended as the Rancher local cluster.` |
| Symbol | Kubernetes or RKE2 logo |
| Type | **Tenant building block** |
| Use in Landing Zone only | **Off** (it should be orderable from the Marketplace) |
| Notification User | platform team mailbox |
| Support / Documentation | link to this repo's `README.md` |

### 1.2 Tags

Optional. To restrict ordering to specific workspaces, set a tag here (for example `environment: platform`) that must match the workspace tag.

### 1.3 Implementation

| Field | Value |
|---|---|
| Implementation type | **OpenTofu** |
| Supported platforms | your **AWS** platform |
| Assignment | **One** (one cluster per tenant) |
| meshStack built-in HTTP backend | **On**. Our code contains no `backend` block (ADR-005). |
| Git repository URL | `git@<git-host>:<org>/<repo>.git` |
| Path in repository | `modules/rke2-cluster/buildingblock` |
| Ref / commit | the release tag, for example `v1.0.0` |
| Authentication | **SSH**. Upload the private deploy key `meshstack_deploy_key`. |
| Known hosts | paste the `ssh-keyscan` output |
| OpenTofu version | the version in `.opentofu-version` (≥ 1.8) |
| Runner | the hosted runner, or your self-hosted runner (prerequisite 4) |
| Pre-Run Script | leave empty (ADR-002) |

After saving, delete the local copy of the private deploy key.

### 1.4 Dependencies

None.

### 1.5 Inputs

Create each input with **Add Input**. The **Name** must exactly match the OpenTofu variable name, or the environment variable name for inputs provided as Environment.

**Credentials and state** (set by the platform team):

| Name | Display name | Source | Type | Provided as | Encrypted | Value |
|---|---|---|---|---|---|---|
| `AWS_REGION` | AWS region | Static | String | Environment | no | from backplane output `aws_region` |
| `AWS_ACCESS_KEY_ID` | Access key ID | Static | String | Environment | **yes** | from backplane output |
| `AWS_SECRET_ACCESS_KEY` | Secret access key | Static | String | Environment | **yes** | from backplane output |
| `TF_VAR_state_encryption_passphrase` | State encryption passphrase | Static | String | Environment | **yes** | from prerequisite 5 |

**meshStack context** (filled in automatically):

| Name | Source | Type | Provided as |
|---|---|---|---|
| `aws_account_id` | Platform Tenant ID | String | Variable |
| `workspace_identifier` | Workspace Identifier | String | Variable |
| `project_identifier` | Project Identifier | String | Variable |
| `building_block_uuid` | Building Block UUID | String | Variable |

**Platform-controlled settings** (required unless marked optional; an optional input left without a value uses the module default shown):

| Name | Source | Type | Value / options |
|---|---|---|---|
| `ami_id` | Static | String | Ubuntu 24.04 amd64 AMI ID of the region (prerequisite 7), for example `ami-0123456789abcdef0` |
| `rke2_version` | Static | String | optional, default `v1.36.6+rke2r1` (Rancher v2.15.2 matrix: RKE2 v1.34 to v1.36). Format `v1.xx.y+rke2rN` |
| `hardening_profile` | Static | Single Select | options `cis`, `none`. Value: `cis` |
| `ingress_controller` | Static | Single Select | optional, only option `traefik` (default). ingress-nginx is retired upstream and rejected |
| `admin_cert_validity_hours` | Static | Integer | optional, default `8760` (24 to 87600) |
| `runner_egress_cidrs` | Static | Code | optional, for example `["203.0.113.10/32"]`. Default `[]` |
| `ingress_allowed_cidrs` | Static | Code | optional, default `["0.0.0.0/0"]` (who may reach 80/443) |
| `public_load_balancer` | Static | Boolean | optional, default `true` (internet-facing NLB for 6443/80/443) |
| `vpc_cidr` | Static | String | optional, default `10.100.0.0/16`, /16 to /24. Must not overlap 10.42.0.0/16 or 10.43.0.0/16 |
| `api_extra_sans` | Static | Code | optional, extra API certificate names, default `[]` |
| `ssh_key_name` | Static | String | optional, EC2 key pair for break-glass SSH from a bastion in the VPC |
| `ssh_allowed_cidrs` | Static | Code | optional, default `[]` (no SSH rule) |
| `root_volume_size_gb` | Static | Integer | optional, default `100` (40 to 16384), gp3 |
| `root_volume_iops` | Static | Integer | optional, default `3000` (3000 to 16000) |
| `kms_key_arn` | Static | String | optional, customer managed KMS key for EBS, the kubeconfig secret and the backup bucket. Grant it in the backplane (`kms_key_arn`) |
| `availability_zones` | Static | Code | optional, max. 4, for example `["eu-central-1a","eu-central-1b","eu-central-1c"]`. Default: first 3 zones of the region |
| `etcd_snapshot_schedule_cron` | Static | String | optional, default `0 */6 * * *` (local and S3) |
| `etcd_snapshot_retention` | Static | Integer | optional, default `10`, ≥ 1. Kept per server, locally and in S3 |
| `backup_force_destroy` | Static | Boolean | optional, default `false`: deleting the building block keeps the backup bucket (the delete run fails until it is emptied). `true` deletes all etcd and Rancher backups with the cluster |
| `rke2_install_script_url` | Static | String | optional, default `https://get.rke2.io` (fetched by the nodes, not the runner) |

**Inputs the ordering user fills in:**

| Name | Display name | Source | Type | Default / options | Validation (regex) |
|---|---|---|---|---|---|
| `cluster_name` | Cluster name | User Input | String | none | `^[a-z][a-z0-9-]{2,30}$`, message "lowercase letters, digits, dashes; 3-31 chars" |
| `server_count` | Number of server nodes | User Input | Single Select | options `1`, `3`, `5`. Default `3` | none |
| `agent_count` | Number of agent nodes | User Input | Integer | **optional** (module default `0`) | none |
| `server_instance_type` | Server node size | User Input | Single Select | amd64 types with ≥ 4 vCPU / 16 GiB, for example `m7i.xlarge`, `m7i.2xlarge`. **optional** (module default `m7i.xlarge`) | none |
| `agent_instance_type` | Agent node size | User Input | Single Select | for example `m7i.large`, `m7i.xlarge`. **optional** (module default matches `server_instance_type`); only used if `agent_count` > 0 | none |
| `api_allowed_cidrs` | Admin CIDRs for API access | User Input | Code | `["10.0.0.0/8"]` | none |

`server_count` uses Single Select. The module declares it as `string` and converts it with `tonumber()`, so it works whether meshStack passes the selection as a string or a number.

Optional inputs send **no value**, so the OpenTofu variable default applies. An optional input must not have a default set in meshStack.

### 1.6 Outputs

Create each output with **Add Output**. The name must match the OpenTofu output.

| Name | Type | Assignment type |
|---|---|---|
| `kubeconfig_secret_name` | String | None |
| `kubeconfig_secret_arn` | String | None |
| `api_server_url` | String | Resource URL |
| `lb_dns_name` | String | None |
| `backup_bucket_name` | String | None |
| `summary` | String | Summary |

**Never map a secret here.** meshStack shows outputs in plaintext and has no sensitive outputs (ADR-012).

### 1.7 Pricing

Optional: a monthly or daily fee charged to the project.

### 1.8 Create and publish

1. Click **Create definition**. It is saved as a **draft**.
2. Click **Submit for publishing**, then **Yes, submit for review**.
3. A meshStack admin approves it, and the status changes to **Published**. Only version 1 needs this review.

### 1.9 Policies tab (after creation)

| Setting | Recommendation | Why |
|---|---|---|
| Building Block Run Control | **Platform Team Only** | Users shouldn't re-run cluster creation. Note that OpenTofu BBs show users no logs in this mode. |
| Run Approvals | **Version upgrade** and **Any input changes** | A changed `server_count` or RKE2 version can replace nodes. Review the `tofu plan` first. |
| Drift Detection & Schedule | **Detect drift only**, Weekly | Never use "Apply automatically" on a cluster, because it can recreate nodes without review. |

---

## 2. Definition `rancher`

Start a new wizard the same way. Only the differences from section 1 are listed here.

### 2.1 General

| Field | Value |
|---|---|
| Definition name | `Rancher Manager` |
| Description | `Installs cert-manager and Rancher on an existing RKE2 cluster and bootstraps the admin account.` |
| Type | **Tenant building block** |

### 2.2 Implementation

| Field | Value |
|---|---|
| Implementation type | OpenTofu |
| Supported platforms | the same AWS platform |
| Assignment | One |
| Built-in HTTP backend | On |
| Git repository / auth / known hosts | same as `rke2-cluster` (the same deploy key works) |
| Path in repository | `modules/rancher/buildingblock` |
| Ref / commit | the same release tag |

### 2.3 Dependencies

Add **`RKE2 Cluster (Rancher management)`** as a dependency. This guarantees the cluster exists first, and enables the **Parent Building Block Output** input source.

### 2.4 Inputs

| Name | Source | Type | Provided as | Encrypted | Value / notes |
|---|---|---|---|---|---|
| `AWS_REGION` | Static | String | Environment | no | as in 1.5 |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | Static | String | Environment | **yes** | as in 1.5; needed for Secrets Manager |
| `TF_VAR_state_encryption_passphrase` | Static | String | Environment | **yes** | use a separate passphrase from the cluster's |
| `aws_account_id` | Platform Tenant ID | String | Variable | no | |
| `workspace_identifier` | Workspace Identifier | String | Variable | no | |
| `project_identifier` | Project Identifier | String | Variable | no | |
| `building_block_uuid` | Building Block UUID | String | Variable | no | |
| `kubeconfig_secret_name` | **Parent Building Block Output** | String | Variable | no | select parent output `kubeconfig_secret_name` (ADR-012) |
| `api_server_url` | **Parent Building Block Output** | String | Variable | no | select parent output `api_server_url` |
| `backup_bucket_name` | **Parent Building Block Output** | String | Variable | no | select parent output `backup_bucket_name` (ADR-014). Parents created before ADR-014 must be upgraded first, or the output does not exist |
| `rancher_version` | Static | String | Variable | no | optional, default `2.15.2`. Chart version **without** `v`; the `rancher2` provider pin must match its minor |
| `cert_manager_version` | Static | String | Variable | no | optional, default `v1.21.2` |
| `rancher_backup_chart_version` | Static | String | Variable | no | optional, default `110.0.3+up11.0.4` (Rancher 2.15 line). Must match the Rancher minor |
| `rancher_backup_schedule` | Static | String | Variable | no | optional, default `0 3 * * *` (UTC), 5-field cron |
| `rancher_backup_retention` | Static | Integer | Variable | no | optional, default `10`, ≥ 1 |
| `rancher_chart_repository` | Static | String | Variable | no | optional, default rancher-stable `https://releases.rancher.com/server-charts/stable`; use the rancher-prime URL if licensed |
| `replicas` | Static | Integer | Variable | no | optional, default `3`. Set to the server count (1 to 3) |
| `ingress_class_name` | Static | String | Variable | no | optional, default `traefik` (RKE2's Traefik class); also used by the Let's Encrypt HTTP-01 solver |
| `kms_key_arn` | Static | String | Variable | no | optional, customer managed KMS key for the admin and backup encryption secrets. Must be the same key as `rke2-cluster` uses, because the backup bucket is encrypted with it |
| `rancher_hostname` | User Input | String | Variable | no | regex `^([a-z0-9-]+\.)+[a-z]{2,}$` |
| `tls_source` | User Input | Single Select | Variable | no | options `rancher`, `letsEncrypt`, `secret`. Default `rancher` |
| `letsencrypt_email` | User Input | String | Variable | no | **Add Condition**: `input.tls_source == "letsEncrypt"` |
| `tls_certificate_pem` | User Input | Code | Variable | **yes** | **Add Condition**: `input.tls_source == "secret"`. PEM certificate with chain |
| `tls_private_key_pem` | User Input | Code | Variable | **yes** | **Add Condition**: `input.tls_source == "secret"`. PEM private key |

The conditions on `letsencrypt_email` and the two PEM inputs hide the fields unless the matching `tls_source` is chosen. While hidden, meshStack sends no value, so the variables have `default = null`, and a `precondition` on the Rancher Helm release requires them when their `tls_source` is selected. Use the **Configuration Preview** next to the input editor to check this behavior before releasing. Whether meshStack can encrypt user inputs depends on your meshStack version; if it cannot, make the PEM inputs Static and encrypted and set them per definition version instead.

### 2.5 Outputs

| Name | Type | Assignment type |
|---|---|---|
| `rancher_url` | String | Resource URL |
| `admin_secret_name` | String | None |
| `admin_secret_arn` | String | None |
| `backup_encryption_secret_name` | String | None |
| `summary` | String | Summary |

### 2.6 Create, publish, policies

The steps are the same as in 1.8 and 1.9. For Run Approvals, **Version upgrade** is enough here, because Rancher upgrades are the risky change.

---

## 3. Test the definitions

1. Pick a **test workspace and project** that has a tenant on the AWS platform.
2. Open **Marketplace**, choose **RKE2 Cluster**, fill in the user inputs, and add the building block to the tenant.
3. Follow the run under **Admin Area → Marketplace → Building Blocks**, or **Platform Builder → Building Blocks → Overview**. Open the run to see the OpenTofu log. Expect about 10 to 25 minutes.
4. Check that the **Summary** shows the API URL and that the outputs `kubeconfig_secret_name` and `kubeconfig_secret_arn` are set. Create the DNS record (CNAME or Route 53 alias) for the Rancher hostname, pointing at output `lb_dns_name`.
5. Add **Rancher Manager** to the same tenant. Then open `rancher_url` from the building block page.
6. Delete both building blocks, child first, and confirm that the destroy runs clean up everything in AWS (VPC, NLBs, instances, EIP, secrets).

## 4. Rolling out changes later

1. Merge the change and tag a new release.
2. Open the definition and click **Create Draft**.
3. Change the **Ref / commit** to the new tag, and adjust inputs and outputs if variables changed. CONTRIBUTING.md rule 12 requires this guide to be updated in the same PR.
4. Click **Release**. New orders use the new version, and existing building blocks keep their version.
5. To upgrade existing instances, go to **Admin Area → Marketplace → Building Blocks**, select them, and click **Upgrade**. With run approvals enabled, the resulting runs wait in **Waiting for Approval** with the plan shown. Review the plan and approve.

## 5. Common errors

| Symptom | Likely cause |
|---|---|
| Clone fails with a host key error | Known hosts are missing or outdated; re-run `ssh-keyscan`. |
| `No value for required variable` | The input name doesn't match the variable name, or a typo in the input Name. |
| State unreadable after a definition change | The state encryption passphrase changed, or the runner changed, so encrypted static inputs can no longer be decrypted. Re-enter the static values in a new version. |
| `rancher` run times out on the API | The runner can't reach port 6443 on the NLB. Check `runner_egress_cidrs` (NLB security group), or use a self-hosted runner. |
| `The AWS credentials belong to account …` | The tenant's account differs from the access key's account (ADR-013). |
| `rancher` run fails on `/ping` | The DNS record for `rancher_hostname` is missing or doesn't point at `lb_dns_name`, or 443 isn't allowed from the runner. |
| More details | [troubleshooting.md](troubleshooting.md) |
| Users see no logs | Expected when Run Control is **Platform Team Only** for OpenTofu building blocks. |

## Alternative: definitions as code

Instead of clicking through the GUI, both definitions can be managed with the `meshcloud/meshstack` OpenTofu provider, as the meshStack Hub modules do through a `meshstack_integration.tf`. Once the GUI setup is proven, consider importing the definitions into code ("How to Import an Existing Building Block Definition into OpenTofu as-code" in the meshStack docs).