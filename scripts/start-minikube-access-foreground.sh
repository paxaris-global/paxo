#!/usr/bin/env bash
# Keep NodePort-aligned forwards alive — run in a dedicated terminal (or via nohup from start-minikube-access.sh).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/local-ports.sh
source "$ROOT_DIR/scripts/local-ports.sh"

echo "Paxo NodePort access (foreground — leave this running)"
echo "Press Ctrl+C to stop."
echo

FORWARDS=(
  "paxo-frontend:${PAXO_FRONTEND_NODE_PORT}:80"
  "keycloak:${PAXO_KEYCLOAK_NODE_PORT}:8080"
  "api-gateway:${PAXO_GATEWAY_NODE_PORT}:8085"
  "identity-service:32087:8087"
  "product-management-service:32088:8088"
  "python-foundry-api:32090:8000"
  "python-frontend:32081:80"
  "jaeger:31686:16686"
)

PIDS=()
cleanup() {
  echo
  echo "Stopping NodePort forwards…"
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
echo "Paxo UI:  http://127.0.0.1:${PAXO_FRONTEND_NODE_PORT}"
echo "Gateway:  http://127.0.0.1:${PAXO_GATEWAY_NODE_PORT}"
echo
wait
