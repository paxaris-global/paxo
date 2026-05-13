#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_PORT="${ARGOCD_LOCAL_PORT:-8081}"
BASE_URL="http://127.0.0.1:${LOCAL_PORT}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' is not installed." >&2
    exit 1
  fi
}

require_cmd kubectl
require_cmd curl
require_cmd python3

if ! nc -z 127.0.0.1 "$LOCAL_PORT" >/dev/null 2>&1; then
  echo "Error: nothing listening on 127.0.0.1:${LOCAL_PORT}." >&2
  echo "Start the UI forward first: ./scripts/start-argocd-ui.sh" >&2
  exit 1
fi

if [[ -n "${ARGOCD_ADMIN_PASSWORD:-}" ]]; then
  PASSWORD="$ARGOCD_ADMIN_PASSWORD"
elif kubectl -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  PASSWORD="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
  if [[ "$PASSWORD" == \$2* ]]; then
    echo "Error: initial admin secret contains a bcrypt hash. Run ./scripts/set-argocd-admin-password.sh or set ARGOCD_ADMIN_PASSWORD." >&2
    exit 1
  fi
else
  echo "Error: argocd-initial-admin-secret not found and ARGOCD_ADMIN_PASSWORD unset." >&2
  exit 1
fi

PAYLOAD="$(ARGOCD_ADMIN_PASSWORD="$PASSWORD" python3 -c 'import json, os; print(json.dumps({"username": "admin", "password": os.environ["ARGOCD_ADMIN_PASSWORD"]}))')"

RESPONSE="$(curl -sS -X POST "${BASE_URL}/api/v1/session" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD")"

if echo "$RESPONSE" | python3 -c 'import sys, json; d=json.load(sys.stdin); sys.exit(0 if d.get("token") else 1)' 2>/dev/null; then
  echo "OK: Argo CD login succeeded (session token returned)."
  exit 0
fi

echo "FAIL: login did not return a token. Response:" >&2
echo "$RESPONSE" >&2
exit 1
