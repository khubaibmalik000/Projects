#!/usr/bin/env bash
# Packages policy/ into an OPA bundle and cryptographically signs it (RS256).
# Generates a throwaway RSA keypair on first run if one isn't already
# present — never commit private keys; in a real deployment the private key
# lives in a secrets manager and only the public key is handed to consumers
# that need to verify bundles.
set -euo pipefail
cd "$(dirname "$0")/.."

KEY_DIR="${KEY_DIR:-.keys}"
mkdir -p "$KEY_DIR"

if [ ! -f "$KEY_DIR/private.pem" ]; then
  openssl genrsa -out "$KEY_DIR/private.pem" 2048 >/dev/null 2>&1
  openssl rsa -in "$KEY_DIR/private.pem" -pubout -out "$KEY_DIR/public.pem" >/dev/null 2>&1
  echo "Generated a new signing keypair in $KEY_DIR/ (gitignored, not for reuse outside this demo)"
fi

opa build -b policy/ --signing-key "$KEY_DIR/private.pem" -o bundle.tar.gz
echo "Built and signed bundle.tar.gz against $KEY_DIR/private.pem"
