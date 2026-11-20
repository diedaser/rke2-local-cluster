# ADR-015: Downstream clusters provisioned by Rancher on EC2

- **Status:** Accepted, 2026-11-20 (proposed the same day). Implemented in `modules/downstream-cluster`; the three points under "Verify in the first implementation" are still open until a real provision has run. Contract and click-path: [meshstack-gui-setup.md](../meshstack-gui-setup.md#3-definition-downstream-cluster).

## Context

The `rke2-cluster` + `rancher` building blocks deliver the Rancher management (`local`) cluster. Teams also need workload ("downstream") clusters managed by that Rancher. They must be orderable through meshStack and follow the existing rules: providers only (ADR-002), secrets in Secrets Manager with references as outputs (ADR-012), one AWS account per credential (ADR-013), strict version pinning (ADR-009).

Options considered:

1. **Rancher-provisioned RKE2 with the Amazon EC2 node driver** (`rancher2_cluster_v2` + `rancher2_machine_config_v2`): Rancher creates, upgrades, scales and deletes the nodes.
2. **Custom nodes:** OpenTofu creates EC2 instances (`_shared/node-pool-aws`) whose cloud-init runs Rancher's registration command. OpenTofu and Rancher then share ownership of the nodes.
3. **Import existing clusters** (for example EKS) with `rancher2_cluster`: no node lifecycle at all.

## Decision

Option 1. A third building block, `downstream-cluster`, with the `rancher` building block as its only parent.

- **Rancher API access (implemented in `rancher`, `downstream-access.tf`):** not the admin token. The `rancher` building block creates the local Rancher user `meshstack-downstream` with exactly the global roles `user-base` and `clusters-create`, and stores its **login** (url, username, password) in Secrets Manager (`<prefix>-rancher-downstream`, output `downstream_credentials_secret_name`). It stores credentials, not a token, because `rancher2_token` always mints for the provider's own (admin) user and Rancher lets users create tokens only for themselves. `downstream-cluster` reads the secret by name (ADR-012) and logs in per run (`POST /v3-public/localProviders/local?action=login` with a short `ttl`) to get a short-lived token for its `rancher2` provider. As the creator, the user owns the clusters it creates, which covers later updates and deletion.
- **EC2 credentials for Rancher (implemented in the backplane, `node-driver.tf`):** the node driver calls EC2 from the Rancher pods, which cannot use the node instance profile (IMDS hop limit 1, ADR-014). The backplane creates a dedicated IAM user (`<iam_user_name>-node-driver`, path `/rke2-node-driver/`) with the policy from Rancher's EC2 guide as a customer managed policy: `RunInstances` and the instance lifecycle actions scoped to the region and account through resource ARNs, the `Resource "*"` actions limited by `aws:RequestedRegion`, the KMS actions only with `kms_key_arn`, and no `iam:PassRole`. Its key arrives as encrypted static inputs and becomes a `rancher2_cloud_credential` per instance, stored in Rancher's database and never output.
- **Network: own VPC, no peering.** Each downstream cluster gets a VPC with private subnets and a NAT gateway, created by the building block. Nodes have no public IPs (`private_address_only = true`). For RKE2 (v2) provisioning, Rancher sends the install script as EC2 user data and does not SSH into the node, so Rancher never needs to reach the downstream VPC. The nodes reach Rancher outbound on 443 through the NAT gateway; the agents keep a reverse tunnel open. The building block creates the node security group (all traffic between the cluster's own nodes, egress all, nothing from any CIDR) and passes it to the driver by name with `security_group_readonly = true`, so Rancher adds no rules of its own.
- **Topology:** control-plane nodes (etcd + control plane, count 1, 3 or 5) and workers (count ≥ 1). A machine config pins one subnet and zone, so each role gets one machine pool per AZ, with the count spread round-robin (3 over 3 AZs = 1+1+1, 5 = 2+2+1); empty pools are omitted. Every pool has its own `rancher2_machine_config_v2` (gp3, encrypted EBS, IMDSv2 required, private address only). The Rancher cluster is named `<cluster_name>-<short building block id>` (ADR-010). User access goes through Rancher's kubeconfig proxy (`https://<rancher>/k8s/clusters/<id>`). The authorized cluster endpoint is not set, so it stays off.
- **Readiness:** `rancher2_cluster_v2` itself waits, for clusters with machine pools, until the provisioning cluster's `Updated` condition is true, and fails early when the condition stays false for 120 s (ADR-007). No `rancher2_cluster_sync` and no sleeps. `timeouts { create = "45m", delete = "45m" }`.
- **Versions:** `kubernetes_version` must be offered by the running Rancher's KDM for RKE2 (ADR-009). The default follows the management cluster's RKE2 minor.
- **Outputs:** cluster name, Rancher cluster ID, Rancher UI link and the NAT gateway's public IP. No kubeconfig (ADR-012): users get theirs from Rancher with their own identity.
- **Scope:** one tenant, the one holding the `rancher` parent, and Rancher's AWS account. Several `downstream-cluster` instances per tenant and per parent (definition flag "only apply once per tenant" off).

## Resolved questions

| Question | Answer | Source |
|---|---|---|
| Does Rancher need SSH (22) into node-driver nodes? | No, not for RKE2 v2 provisioning: the install script goes in as user data, and `rancher/machine` returns before the SSH step. The Rancher port table still lists 22; that row stems from RKE1. | `rancher/rancher` `pkg/controllers/capr/machineprovision/args.go` (`--custom-install-script`); `rancher/machine` `libmachine/libmachine.go` `performCreate`; [port requirements](https://ranchermanager.docs.rancher.com/getting-started/installation-and-upgrade/installation-requirements/port-requirements) |
| Which paths are required? | Downstream nodes → Rancher 443 (outbound). Between downstream nodes: 6443, 9345, 10250, 2379-2381, 8472/UDP, 9099. | [communicating with downstream clusters](https://ranchermanager.docs.rancher.com/reference-guides/rancher-manager-architecture/communicating-with-downstream-user-clusters), port requirements |
| Does `rancher2_cluster_v2` wait for Active? | Yes for clusters with machine pools: waits for condition `Created`, then `Updated`; polls every 5 s; create timeout (default 30m) also applies to updates. | provider v15.3.0 `rancher2/resource_rancher2_cluster_v2.go` L121-131, L420-463 |
| Is `rancher2_cluster_sync` needed? | No. It repeats the same `Updated` wait. With the authorized cluster endpoint on, its `Connected` loop has no timeout bound. | provider v15.3.0 `resource_rancher2_cluster_sync.go` L64, L84-87 |
| Does destroy wait for the machines? | It waits until the v2 and v3 cluster objects are removed (delete timeout). Rancher's finalizers delete the machines first; the provider does not check EC2 itself. | provider v15.3.0 `resource_rancher2_cluster_v2.go` L246-311 |
| Child in another tenant than its parent? | Not documented; all evidence points to same-tenant dependency graphs. No native cross-tenant output sharing. | [meshStack building block concept](https://docs.meshcloud.io/concepts/building-block/) |
| Several children per parent / per tenant? | Yes: each child has exactly one parent per dependency, several children of one definition per parent are a documented pattern, and multiple instances per tenant are allowed unless `only_apply_once_per_tenant` is set. | concept page; meshStack provider `building_block_definition.md` |
| Grandparent outputs? | Only outputs of declared dependencies are selectable. Not needed any more: without peering, `downstream-cluster` uses `rancher` outputs only. | meshStack provider `building_block_definition.md` (`BUILDING_BLOCK_OUTPUT`) |
| Does meshStack delete children before the parent? | Not documented as enforced. Treat child-first deletion as an operator rule. | concept page |
| Quotas and cost | NAT gateway ≈ $0.052/h + $0.052/GB in eu-central-1 per downstream cluster (verify in the AWS Pricing Calculator). No peering, so the peering quota (50 per VPC) does not apply. | [VPC pricing](https://aws.amazon.com/vpc/pricing/) |

## Consequences

- Two changes before the module itself: the `rancher` downstream user, secret and output, and the backplane node-driver IAM user (both done). No change to `rke2-cluster`.
- The downstream user must never be replaced: a new user ID would leave the existing downstream clusters without their owner. Its password is rotated in place (`docs/operations.md`).
- If `ingress_allowed_cidrs` of the management NLB is ever restricted, it must include every downstream NAT IP (output `nat_public_ip`), or the agents cannot reach Rancher and the cluster never becomes active.
- Rancher owns the downstream nodes. OpenTofu owns the cluster object, the machine configs, the cloud credential, the VPC and the security group. Deleting the building block deletes the cluster in Rancher, which terminates the instances; the VPC is destroyed after the cluster (it references the subnets and security group).
- The management cluster is a dependency of every downstream cluster's lifecycle (scale, upgrade, delete), not of its runtime: workloads keep running if Rancher is down.
- Deleting `rancher` while `downstream-cluster` children exist would orphan them in AWS. meshStack does not prevent it; the operations guide must state children first.
- The node-driver key is long-lived and needs the same rotation as the runner key.
- Application teams cannot order downstream clusters in their own tenants with this design. That needs a different source for the Rancher URL and token (static inputs plus a cross-account secret) and per-account node-driver credentials; it is a separate ADR.

## Verify in the first implementation

1. A real provision with private-only nodes and no route from the management VPC succeeds (confirms the no-SSH code path).
2. The node-driver IAM policy without tag conditions works as documented; tag-based conditions are added only after testing them.
3. After `tofu destroy`, no `rancher-node-driver` instances or ENIs remain before the VPC delete starts. If they do, add an explicit wait.
