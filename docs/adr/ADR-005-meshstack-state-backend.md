# ADR-005: meshStack built-in state backend, one state per instance

- **Status:** Accepted, 2026-10-16

## Context

meshStack provides a built-in HTTP backend keyed by workspace and building block UUID, and handles its authentication itself. A `backend` block in source takes precedence over the injected backend.

## Decision

- Enable the built-in HTTP backend on both definitions.
- Never commit a `backend` block under `modules/`. `scripts/validate-all.sh` enforces this.
- `examples/standalone/` and the backplane use local state or a git-ignored `backend_override.tf`.
- Cross-building-block data flows only through meshStack input/output mappings, never through `terraform_remote_state`.

## Consequences

- The backend has no locking. meshStack runs one run at a time per building block, but never run the same instance from outside meshStack in parallel.
