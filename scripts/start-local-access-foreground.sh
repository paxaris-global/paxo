#!/usr/bin/env bash
# Keep all port-forwards alive — run in a dedicated terminal tab (do not close).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/local-ports.sh
source "$ROOT_DIR/scripts/local-ports.sh"

echo "Paxaris local access (foreground — leave this terminal open)"
echo "Press Ctrl+C to stop all forwards."
echo

FORWARDS=(
  "paxo-frontend:${PAXO_FRONTEND_LOCAL_PORT}:80"
  "keycloak:${PAXO_KEYCLOAK_LOCAL_PORT}:8080"
  "api-gateway:${PAXO_GATEWAY_LOCAL_PORT}:8085"
  "identity-service:${PAXO_IDENTITY_LOCAL_PORT}:8087"
  "product-management-service:${PAXO_PRODUCT_LOCAL_PORT}:8088"
  "python-foundry-api:${PAXO_PYTHON_FOUNDRY_API_LOCAL_PORT}:8000"
  "python-frontend:${PAXO_PYTHON_FRONTEND_LOCAL_PORT}:80"
  "jaeger:${PAXO_JAEGER_LOCAL_PORT}:16686"
)

PIDS=()
cleanup() {
  echo
  echo "Stopping port-forwards..."
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  exit 0
}
trap cleanup TERM INT

for spec in "${FORWARDS[@]}"; do
  IFS=':' read -r svc local remote <<<"$spec"
  kubectl -n default port-forward "svc/$svc" "${local}:${remote}" --address 127.0.0.1 &
  PIDS+=($!)
  echo "  svc/$svc -> http://127.0.0.1:${local}"
done

echo
echo "Frontend:  http://localhost:${PAXO_FRONTEND_LOCAL_PORT}"
echo "Gateway:   http://localhost:${PAXO_GATEWAY_LOCAL_PORT}"
echo "Keycloak:  http://localhost:${PAXO_KEYCLOAK_LOCAL_PORT}"
echo
wait
