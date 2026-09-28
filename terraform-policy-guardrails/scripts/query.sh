#!/usr/bin/env bash
# Plans a Terraform directory and asks a running policy-decision server
# (scripts/serve.sh) whether it violates the guardrails, over HTTP — the
# same check as scripts/check.sh, but against a centrally hosted policy
# service instead of a locally bundled copy of the Rego files.
#
# Usage: scripts/query.sh <path-to-terraform-dir> [server-url]
set -euo pipefail

DIR="${1:?Usage: query.sh <path-to-terraform-dir> [server-url]}"
URL="${2:-http://localhost:8181}/v1/data/terraform/guardrails/deny"

PYTHON="${PYTHON:-python3}"
command -v "$PYTHON" >/dev/null 2>&1 || PYTHON=python

pushd "$DIR" >/dev/null
terraform init -input=false >/dev/null
terraform plan -input=false -out=plan.tfplan >/dev/null
terraform show -json plan.tfplan | "$PYTHON" -c 'import json, sys; json.dump({"input": json.load(sys.stdin)}, sys.stdout)' >query.json
rm -f plan.tfplan
popd >/dev/null

RESPONSE=$(curl -s -X POST "$URL" -H "Content-Type: application/json" --data-binary @"$DIR/query.json")
rm -f "$DIR/query.json"

VIOLATIONS=$(echo "$RESPONSE" | "$PYTHON" -c 'import json, sys; print(json.dumps(json.load(sys.stdin).get("result", [])))')

if [ "$(echo "$VIOLATIONS" | tr -d '[:space:]')" = "[]" ]; then
  echo "PASS (via policy server): no violations in $DIR"
  exit 0
fi

echo "FAIL (via policy server): violations in $DIR"
echo "$VIOLATIONS"
exit 1
