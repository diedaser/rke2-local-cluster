# ADR-006: Fixed registration address through a load balancer

- **Status:** Accepted, 2026-10-16. Revised 2026-11-18 for AWS (was: one Octavia LB with floating IP).

## Context

Nodes need a stable address to register with, and the runner needs one stable API endpoint. Server nodes must be replaceable without re-joining the whole cluster.

## Decision

- AWS Network Load Balancers (`loadbalancer.tf`), TCP listeners, one target group per listener (instance targets, TCP health checks, cross-zone load balancing, listener TCP idle timeout 1 hour so watches are not cut):
  - **internal** NLB (always, private subnets): 6443 (API) and 9345 (supervisor). The registration address is `https://<internal NLB DNS>:9345`.
  - **public** NLB (`public_load_balancer = true`, the default; public subnets): 6443, 80, 443 for clients. 9345 is never public.
  - With `public_load_balancer = false` the internal NLB also serves clients on 80/443, and its 6443 listener accepts the client CIDRs.
- Client filtering happens on the NLB security groups (NLBs support security groups since 2023):
  - 6443: `api_allowed_cidrs` + `runner_egress_cidrs` (+ VPC CIDR on the internal NLB)
  - 9345: VPC CIDR only
  - 80/443: `ingress_allowed_cidrs` + `runner_egress_cidrs` (+ VPC CIDR on the internal NLB)
  - public NLB additionally: the cluster's NAT gateway EIP on 6443/80/443, so pods can reach the Rancher hostname (hairpin through NAT) even with restricted allow lists.
- **Client IP preservation is disabled** on all target groups. With preservation, a node connecting through the NLB to a target that is itself (registration on 9345, pods hitting the Rancher hostname) drops the connection. Consequence: nodes only accept LB traffic from the NLB security groups, and ingress logs show NLB addresses, not client addresses. Proxy protocol v2 is the fix if client IPs are needed later.
- `tls-san` contains both NLB DNS names and `api_extra_sans`. NLBs have no stable IPs, so there are no IP SANs.
- RKE2 always runs embedded etcd and has no `cluster-init` flag (unlike K3s). The first server (`module.server_init`) is the one whose config has no `server:` key. Joining servers (`module.server_join`) set `server: https://<internal NLB>:9345` and `depends_on` the first server.
- Server instances use the "pinned" variant of `_shared/node-pool-aws`. It ignores changes to `ami`, `user_data_base64`, `subnet_id`, `key_name` and `placement_group`, so OpenTofu never silently replaces an etcd member. Servers share a `spread` placement group and are spread round-robin over the private subnets (one per AZ).

## Consequences

- RKE2 upgrades on servers are a manual rolling procedure ([operations](../operations.md#rke2-upgrades)).
- `module.server_init` index 0 must not be replaced casually ([operations](../operations.md#replacing-a-server)).
- The Rancher DNS record is a CNAME (or Route 53 alias) to the NLB DNS name, not an A record.
- NLB target registration takes several minutes; readiness polling allows 20 minutes ([ADR-007](ADR-007-readiness-polling.md)).
- Two NLBs cost twice the hourly LB charge. Accepted: it keeps 9345 off the internet and node registration independent of public DNS.
