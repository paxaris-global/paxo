#!/usr/bin/env bash
# Creates a Keycloak realm via POST /identity/signup (same as Sign up in the UI).
# After this, log in with:
#   Realm:     $REALM_NAME
#   Client ID: ${REALM_NAME}-admin-product
#   Username:  admin
#   Password:  the ADMIN_PASSWORD you set here
#
# Requires API Gateway reachable — from host with port-forward:
#   ./scripts/start-local-access.sh
# Default gateway URL: http://localhost:8085
#
# Usage:
#   REALM_NAME=vipultest ADMIN_PASSWORD='admin@123' ./scripts/bootstrap-dev-realm.sh
#
set -euo pipefail

REALM_NAME="${REALM_NAME:-vipultest}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:?Set ADMIN_PASSWORD (e.g. export ADMIN_PASSWORD='YourPass!1')}"
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8085}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing command: $1" >&2
    exit 1
  }
}

require_cmd curl

payload="$(printf '{"realmName":"%s","adminPassword":"%s"}' "${REALM_NAME}" "${ADMIN_PASSWORD}")"

OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

echo "POST ${GATEWAY_URL}/identity/signup (realm=${REALM_NAME})"
code="$(curl -sS -o "$OUT" -w '%{http_code}' -X POST "${GATEWAY_URL}/identity/signup" \
  -H 'Content-Type: application/json' \
  -d "${payload}")"

cat "$OUT"
echo
echo "HTTP ${code}"

if [[ "${code}" == "201" ]] || [[ "${code}" == "409" ]]; then
  echo
  echo "Login in the UI with:"
  echo "  Realm:      ${REALM_NAME}"
  echo "  Client ID:  ${REALM_NAME}-admin-product"
  echo "  Username:   admin"
  echo "  Password:   (the ADMIN_PASSWORD you used)"
  exit 0
fi

exit 1
