# ADR-011: CIS hardening profile by default

- **Status:** Accepted, 2026-10-16

## Decision

`hardening_profile = "cis"` is the default (`none` is allowed for dev). With `cis`:

- RKE2 runs with `profile: cis`.
- cloud-init writes `/etc/sysctl.d/90-rke2-cis.conf` (`vm.panic_on_oom=0`, `vm.overcommit_memory=1`, `kernel.panic=10`, `kernel.panic_on_oops=1`) and runs `sysctl --system` before RKE2 is installed.
- On servers, cloud-init creates the `etcd` system user.
- Servers get a Pod Security Admission config at `/etc/rancher/rke2/rancher-psa.yaml` (`pod-security-admission-config-file`). It enforces `restricted` by default and exempts the Rancher, Fleet, cert-manager, ingress and system namespaces, following the rancher-restricted template from the Rancher hardening guide.

## Consequences

- Workloads in namespaces that are not exempted must comply with `restricted` ([troubleshooting](../troubleshooting.md#psa-violations-under-the-cis-profile)).
- Changing the exemption list affects only new servers, because server `user_data` changes are ignored ([ADR-006](ADR-006-fixed-registration-address.md)). Existing servers must be edited by hand.
