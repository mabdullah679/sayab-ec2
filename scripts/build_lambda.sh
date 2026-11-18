#!/usr/bin/env bash
# Build the Lambda zip: handler + app + templates/ + frontend/ (+ Linux/arm64 deps).
# Env: OUT (default dist/lambda.zip), SKIP_DEPS=1 (app files only, used by unit tests).
# No AWS calls; the dependency step only needs PyPI.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/dist/lambda.zip}"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

if [ "${SKIP_DEPS:-}" != "1" ]; then
  python3 -m pip install --quiet --target "$STAGE" \
    --platform manylinux2014_aarch64 --python-version 3.12 --implementation cp \
    --only-binary=:all: -r "$ROOT/requirements-lambda.txt"
fi

cp "$ROOT/backend/app.py" "$ROOT/backend/lambda_handler.py" "$STAGE/"
cp -R "$ROOT/backend/templates" "$STAGE/templates"
cp -R "$ROOT/frontend" "$STAGE/frontend"
find "$STAGE" -name __pycache__ -type d -prune -exec rm -rf {} +
find "$STAGE" -name '*.dist-info' -type d -prune -exec rm -rf {} +

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
(cd "$STAGE" && python3 - "$OUT" <<'PY'
import os, sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as z:
    for d, _, fs in sorted(os.walk(".")):
        for f in sorted(fs):
            p = os.path.join(d, f)
            z.write(p, os.path.relpath(p, "."))
PY
)
echo "built $OUT ($(wc -c < "$OUT") bytes)"
