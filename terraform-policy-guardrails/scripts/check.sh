#!/usr/bin/env bash
# Plans a Terraform directory and evaluates it against the OPA guardrails.
# Exits non-zero and prints each violation if any `deny` rule fires.
#
# Usage: scripts/check.sh <path-to-terraform-dir>
set -euo pipefail

DIR="${1:?Usage: check.sh <path-to-terraform-dir>}"
POLICY_DIR="$(cd "$(dirname "$0")/../policy" && pwd)"

pushd "$DIR" >/dev/null
terraform init -input=false >/dev/null
terraform plan -input=false -out=plan.tfplan >/dev/null
terraform show -json plan.tfplan >plan.json
rm -f plan.tfplan
popd >/dev/null

VIOLATIONS=$(opa eval --format raw -d "$POLICY_DIR/terraform.rego" -i "$DIR/plan.json" "data.terraform.guardrails.deny")
rm -f "$DIR/plan.json"

if [ "$(echo "$VIOLATIONS" | tr -d '[:space:]')" = "[]" ]; then
  echo "PASS: no policy violations in $DIR"
  exit 0
fi

echo "FAIL: policy violations in $DIR"
echo "$VIOLATIONS"
exit 1
