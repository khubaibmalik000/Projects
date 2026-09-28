#!/usr/bin/env bash
# Serves the signed bundle as a live policy-decision API (a "PDP" in OPA's
# terms) — the pattern a real platform team uses to run policy as a shared
# service that many CI pipelines query, instead of vendoring a copy of the
# Rego files into every consumer. OPA verifies the bundle's signature
# against the public key before it will load it at all; a tampered or
# unsigned bundle is refused outright, not silently trusted.
set -euo pipefail
cd "$(dirname "$0")/.."

KEY_DIR="${KEY_DIR:-.keys}"
ADDR="${ADDR:-:8181}"

if [ ! -f bundle.tar.gz ]; then
  echo "bundle.tar.gz not found — run scripts/build-signed-bundle.sh first" >&2
  exit 1
fi

exec opa run --server --addr "$ADDR" --bundle bundle.tar.gz \
  --verification-key "$KEY_DIR/public.pem" --verification-key-id "portfolio-demo"
