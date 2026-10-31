# ADR-006: Fixed registration address through a load balancer

- **Status:** Accepted, 2026-10-16

## Context

Nodes need a stable address to register with, and the runner needs one stable API endpoint. Server nodes must be replaceable without re-joining the whole cluster.

## Decision

- One Octavia load balancer (`loadbalancer.tf`) with TCP listeners and pools for 6443 (API), 9345 (supervisor), 80 and 443 (ingress). Each pool has a TCP health monitor. Client and member data timeouts are 1 hour, so watches are not cut.
- Listener `allowed_cidrs`:
  - 6443: `api_allowed_cidrs` + `runner_egress_cidrs` + `subnet_cidr`
  - 9345: `subnet_cidr` only
  - 80/443: `ingress_allowed_cidrs` + `runner_egress_cidrs` + `subnet_cidr`

  The subnet is always included, so the list is never empty (an empty list means "allow all").
- A floating IP is associated with the VIP port when `assign_floating_ip = true` (the default). The API URL uses the floating IP. Nodes register through the private VIP (`https://<vip>:9345`).
- `tls-san` contains the VIP, the floating IP and `api_extra_sans`.
- RKE2 always runs embedded etcd and has no `cluster-init` flag (unlike K3s). The first server (`module.server_init`) is the one whose config has no `server:` key. Joining servers (`module.server_join`) set `server: https://<vip>:9345` and `depends_on` the first server.
- Server instances use the "pinned" variant of `_shared/node-pool-openstack`. It ignores changes to `user_data`, `image_id`, `image_name`, `block_device`, `key_pair` and `availability_zone`, so OpenTofu never silently replaces an etcd member. Servers share a `soft-anti-affinity` server group.

## Consequences

- RKE2 upgrades on servers are a manual rolling procedure ([operations](../operations.md#rke2-upgrades)).
- `module.server_init` index 0 must not be replaced casually ([operations](../operations.md#replacing-a-server)).
- Octavia must support listener `allowed_cidrs` (API version 2.12 or later).
