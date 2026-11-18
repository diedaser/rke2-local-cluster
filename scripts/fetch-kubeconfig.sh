#!/usr/bin/env bash
# Break-glass: fetch the admin kubeconfig of an rke2-cluster building block
# from AWS Secrets Manager. Platform team only.
#
# The building block never outputs the kubeconfig (ADR-012); it lives in
# Secrets Manager in the tenant's AWS account. Requires the `aws` CLI v2 with
# credentials for that account (AWS_PROFILE or AWS_ACCESS_KEY_ID/...) and
# AWS_REGION set to the cluster's region (or pass an ARN).
#
# Usage: scripts/fetch-kubeconfig.sh <kubeconfig_secret_arn | kubeconfig_secret_name> [output-file]
#   Both values are shown in the building block's outputs/summary in meshStack.
#   Default output file: ./kubeconfig-<name> (mode 0600, git-ignored).
set -euo pipefail

if [[ $# -lt 1 ]]; then
  sed -n '2,13p' "$0" >&2
  exit 2
fi

id="$1"
region_args=()
if [[ "$id" == arn:* ]]; then
  # arn:aws:secretsmanager:<region>:<account>:secret:<name>-<suffix>
  region_args=(--region "$(cut -d: -f4 <<<"$id")")
  name="$(cut -d: -f7 <<<"$id")"
else
  name="$id"
fi

out="${2:-./kubeconfig-${name}}"
umask 077
aws secretsmanager get-secret-value "${region_args[@]}" --secret-id "$id" \
  --query SecretString --output text > "$out"
chmod 600 "$out"
echo "Wrote $out. Use: KUBECONFIG=$out kubectl get nodes" >&2
echo "Delete the file when done; it grants cluster-admin." >&2
