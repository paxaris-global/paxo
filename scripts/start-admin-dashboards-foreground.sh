#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/local-ports.sh
source "$ROOT_DIR/scripts/local-ports.sh"

ts() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

KEYCLOAK_LOCAL_PORT="${PAXO_KEYCLOAK_NODE_PORT}"
ARGOCD_LOCAL_PORT="${PAXO_ARGOCD_LOCAL_PORT}"

start_forward() {
  local ns="$1"
  local svc="$2"
  local local_port="$3"
  local remote_port="$4"
  local label="$5"

  while true; do
    printf "[%s] port-forward svc/%s %s:%s (%s)\n" "$(ts)" "$svc" "$local_port" "$remote_port" "$label"
    kubectl -n "$ns" port-forward "svc/$svc" "${local_port}:${remote_port}" --address 127.0.0.1 &
    child=$!
    wait "$child"
    printf "[%s] %s port-forward exited; restarting in 2s\n" "$(ts)" "$label"
    sleep 2
  done
}

PIDS=()
cleanup() {
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  exit 0
}
trap cleanup TERM INT

if kubectl -n default get svc keycloak >/dev/null 2>&1; then
  start_forward default keycloak "$KEYCLOAK_LOCAL_PORT" 8080 keycloak &
  PIDS+=($!)
  echo "Keycloak admin: http://localhost:${KEYCLOAK_LOCAL_PORT}/admin/"
fi

if kubectl -n argocd get svc argocd-server >/dev/null 2>&1; then
  start_forward argocd argocd-server "$ARGOCD_LOCAL_PORT" 80 argocd &
  PIDS+=($!)
  echo "Argo CD UI:     http://127.0.0.1:${ARGOCD_LOCAL_PORT}"
fi

wait
