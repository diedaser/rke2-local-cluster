#!/usr/bin/env bash
# Break-glass: fetch the Rancher admin credentials of a rancher building block
# from AWS Secrets Manager. Platform team only.
#
# The building block never outputs credentials (ADR-012); they live in the
# secret <prefix>-rancher-admin in the tenant's AWS account. Requires the `aws`
# CLI v2 and `jq`, credentials for that account (AWS_PROFILE or
# AWS_ACCESS_KEY_ID/...) and AWS_REGION set to the cluster's region (or pass
# an ARN).
#
# Usage: scripts/fetch-rancher-admin.sh [admin_secret_arn | admin_secret_name]
#   Both values are shown in the building block's outputs/summary in meshStack.
#   Without an argument, the single secret ending in -rancher-admin in the
#   region is used; with several, they are listed and the script fails.
#   URL and username go to stderr, the password alone to stdout, so it can be
#   piped (e.g. into a clipboard tool) without landing in scrollback.
set -euo pipefail

usage() { sed -n '2,16p' "$0" >&2; exit 2; }

[[ $# -le 1 ]] || usage
[[ "${1:-}" != -h && "${1:-}" != --help ]] || usage
command -v jq >/dev/null || { echo "jq is required." >&2; exit 1; }

region_args=()
if [[ $# -eq 1 ]]; then
  id="$1"
  if [[ "$id" == arn:* ]]; then
    # arn:aws:secretsmanager:<region>:<account>:secret:<name>-<suffix>
    region_args=(--region "$(cut -d: -f4 <<<"$id")")
  fi
else
  # The Secrets Manager name filter matches prefixes only, so search by suffix
  # client-side.
  mapfile -t matches < <(aws secretsmanager list-secrets \
    --query "SecretList[?ends_with(Name, '-rancher-admin')].Name" --output text | tr '\t' '\n' | sed '/^$/d')
  case ${#matches[@]} in
    0) echo "No *-rancher-admin secret in region ${AWS_REGION:-<unset>}. Has the rancher building block finished bootstrap?" >&2; exit 1 ;;
    1) id="${matches[0]}" ;;
    *) printf 'Several Rancher admin secrets; pass one:\n' >&2; printf '  %s\n' "${matches[@]}" >&2; exit 1 ;;
  esac
fi

secret="$(aws secretsmanager get-secret-value "${region_args[@]}" --secret-id "$id" \
  --query SecretString --output text)"

jq -r '"URL:      \(.url)\nUsername: \(.username)"' <<<"$secret" >&2
jq -r '.password' <<<"$secret"
