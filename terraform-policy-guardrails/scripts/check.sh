#!/usr/bin/env bash
# Plans a Terraform directory and evaluates it against the OPA guardrails.
# Exits non-zero and prints each unwaived violation if any `deny` rule
# fires, plus a severity/waiver breakdown from `report`.
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

# -d "$POLICY_DIR" (not just terraform.rego) so waivers.rego loads too.
REPORT=$(opa eval --format raw -d "$POLICY_DIR" -i "$DIR/plan.json" "data.terraform.guardrails.report")
VIOLATIONS=$(opa eval --format raw -d "$POLICY_DIR" -i "$DIR/plan.json" "data.terraform.guardrails.deny")
rm -f "$DIR/plan.json"

echo "Report: $REPORT"

if [ "$(echo "$VIOLATIONS" | tr -d '[:space:]')" = "[]" ]; then
  echo "PASS: no policy violations in $DIR"
  exit 0
fi

echo "FAIL: policy violations in $DIR"
echo "$VIOLATIONS"
exit 1
