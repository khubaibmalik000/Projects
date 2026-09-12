#!/usr/bin/env bash
# Packages src/ into function.zip, the deployment artifact Terraform
# points at via `lambda_zip_path`. Run this before `terraform plan/apply`
# whenever the handler changes. Uses Python's zipfile module instead of the
# `zip` CLI so this works the same on Linux CI runners and on Windows/Git Bash.
set -euo pipefail
cd "$(dirname "$0")"

PYTHON="${PYTHON:-python3}"
command -v "$PYTHON" >/dev/null 2>&1 || PYTHON=python

rm -rf build
mkdir -p build
cp src/handler.py build/

if [ -s requirements.txt ] && grep -qv '^\s*#' requirements.txt; then
  "$PYTHON" -m pip install -r requirements.txt -t build --quiet
fi

rm -f function.zip
"$PYTHON" - <<'PY'
import os
import zipfile

with zipfile.ZipFile("function.zip", "w", zipfile.ZIP_DEFLATED) as zf:
    for root, _dirs, files in os.walk("build"):
        for name in files:
            path = os.path.join(root, name)
            zf.write(path, os.path.relpath(path, "build"))
PY
rm -rf build

echo "Built function.zip ($(du -h function.zip | cut -f1))"
