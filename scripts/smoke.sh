#!/usr/bin/env bash
# Smoke test a deployed URL. Usage: scripts/smoke.sh http://host
set -euo pipefail
URL="${1:?usage: smoke.sh <base-url>}"

for i in $(seq 1 40); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL/readyz" || true)
  [ "$code" = "200" ] && break
  echo "waiting for $URL/readyz (got $code) [$i/40]"; sleep 10
done
[ "$code" = "200" ] || { echo "FAIL: /readyz never returned 200"; exit 1; }

check() { # description, expected substring, actual
  case "$3" in *"$2"*) echo "ok   $1";; *) echo "FAIL $1: expected '$2' in: $3"; exit 1;; esac
}
check "healthz"        '"status":"ok"'  "$(curl -fsS "$URL/healthz" | tr -d ' \n')"
check "home form"      'name="user_name"' "$(curl -fsS "$URL/")"
check "stylesheet"     'background-color' "$(curl -fsS "$URL/static/styles.css")"
check "greeting"       'Jane Doe'    "$(curl -fsS -d 'user_name=jane doe' "$URL/submit")"
body=$(curl -fsS -d 'user_name=<script>x</script>' "$URL/submit")
case "$body" in *"<script>x"*) echo "FAIL xss reflected"; exit 1;; *) echo "ok   xss escaped";; esac
code=$(curl -s -o /dev/null -w '%{http_code}' -d "user_name=$(printf 'a%.0s' $(seq 1 61))" "$URL/submit")
[ "$code" = "400" ] && echo "ok   overlong name -> 400" || { echo "FAIL overlong gave $code"; exit 1; }
curl -fsSI "$URL/" | grep -qi '^x-content-type-options: nosniff' && echo "ok   security headers"
echo "SMOKE PASSED"
