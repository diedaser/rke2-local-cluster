# ADR-013: Credentials are scoped to the tenant's AWS account

- **Status:** Accepted, 2026-10-16. Revised 2026-11-18 for AWS (was: OpenStack project / application credential).

## Context

The runner authenticates with an IAM user access key (static inputs, from the backplane). The key belongs to one AWS account. meshStack passes the tenant's account through the Platform Tenant ID (`aws_account_id`), which may differ per meshProject.

## Decision

Both building blocks read `data.aws_caller_identity.current` and fail when its `account_id` differs from `aws_account_id`:

- `rke2-cluster`: precondition on `aws_vpc.this`
- `rancher`: precondition on `data.http.api_readyz`

Nothing is created in the wrong account.

## Consequences

- One definition with one access key serves exactly one AWS account (and, through the backplane policy, one region).
- Options for multiple accounts (future work):
  - one definition (or definition version with different static inputs) per account, each with its own backplane IAM user
  - a hub identity that assumes a role in the tenant account (`assume_role { role_arn = "arn:aws:iam::${var.aws_account_id}:role/..." }`), with the role provisioned by the meshStack AWS replicator. Verify against the meshStack docs whether workload identity federation is available for building block runners before building this (CONTRIBUTING.md rule 13).
