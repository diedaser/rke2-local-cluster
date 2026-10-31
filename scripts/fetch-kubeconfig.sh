#!/usr/bin/env bash
# Break-glass: fetch the admin kubeconfig of an rke2-cluster building block
# from OpenStack Barbican. Platform team only.
#
# The building block never outputs the kubeconfig (ADR-012); it lives in
# Barbican in the tenant's OpenStack project. Requires the `openstack` CLI
# with python-barbicanclient and credentials for that project (source an
# openrc or set OS_CLOUD).
#
# Usage: scripts/fetch-kubeconfig.sh <kubeconfig_secret_ref | kubeconfig_secret_name> [output-file]
#   Both values are shown in the building block's outputs/summary in meshStack.
#   Default output file: ./kubeconfig-<name> (mode 0600, git-ignored).
set -euo pipefail

if [[ $# -lt 1 ]]; then
  sed -n '2,14p' "$0" >&2
  exit 2
fi

ref="$1"
if [[ "$ref" != http*://* ]]; then
  # Resolve a secret name to its reference.
  ref="$(openstack secret list --name "$1" -f value -c "Secret href")"
  count="$(printf '%s\n' "$ref" | grep -c . || true)"
  if [[ "$count" -ne 1 ]]; then
    echo "ERROR: expected exactly one Barbican secret named '$1', found $count" >&2
    exit 1
  fi
fi

out="${2:-./kubeconfig-$(basename "$1")}"
umask 077
openstack secret get --payload -f value "$ref" > "$out"
chmod 600 "$out"
echo "Wrote $out. Use: KUBECONFIG=$out kubectl get nodes" >&2
echo "Delete the file when done; it grants cluster-admin." >&2
