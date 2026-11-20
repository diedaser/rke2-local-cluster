#!/usr/bin/env bash
# fmt -check, init -backend=false, validate, tflint and tofu test over every
# OpenTofu root and module in the repo. Never touches real infrastructure.
#
# Usage: ./scripts/validate-all.sh
# Env:   TOFU (default: tofu), TFLINT (default: tflint, skipped if missing)
set -euo pipefail

cd "$(dirname "$0")/.."
TOFU="${TOFU:-tofu}"
TFLINT="${TFLINT:-tflint}"
REPO_ROOT="$(pwd)"
failed=0

step() { printf '\n==> %s\n' "$*"; }

step "tofu fmt -check -recursive"
"$TOFU" fmt -check -recursive -diff || failed=1

dirs=(
  modules/_shared/naming
  modules/_shared/node-pool-aws
  modules/rke2-cluster/buildingblock
  modules/rke2-cluster/backplane
  modules/rancher/buildingblock
  modules/downstream-cluster/buildingblock
  examples/standalone
  examples/standalone/downstream
)

have_tflint=1
if ! command -v "$TFLINT" >/dev/null 2>&1; then
  echo "WARN: tflint not found, skipping lint" >&2
  have_tflint=0
else
  "$TFLINT" --init --config "$REPO_ROOT/.tflint.hcl" >/dev/null
fi

for d in "${dirs[@]}"; do
  step "$d"
  (
    cd "$d"
    "$TOFU" init -backend=false -input=false -no-color >/dev/null
    "$TOFU" validate -no-color
    if [[ $have_tflint -eq 1 ]]; then
      "$TFLINT" --config "$REPO_ROOT/.tflint.hcl" --no-color
    fi
    if [[ -d tests ]]; then
      "$TOFU" test -no-color
    fi
  ) || failed=1
done

# Guard rails from CONTRIBUTING.md that tooling does not catch.
step "guard rails (ADR-002, ADR-005, rule 11)"
if grep -rnE 'local-exec|remote-exec|data "external"' --include='*.tf' modules examples; then
  echo "ERROR: provisioners or external data sources are forbidden (ADR-002)" >&2
  failed=1
fi
if grep -rnE '^\s*backend\s+"' --include='*.tf' modules; then
  echo "ERROR: backend blocks are forbidden in modules (ADR-005)" >&2
  failed=1
fi
if grep -rn 'sensitive *= *true' modules/*/buildingblock/outputs.tf; then
  echo "ERROR: building blocks must not output secrets (ADR-012, rule 11)" >&2
  failed=1
fi

if [[ $failed -ne 0 ]]; then
  printf '\nFAILED\n' >&2
  exit 1
fi
printf '\nAll checks passed.\n'
