#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.local-runtime"
PID_FILE="$RUNTIME_DIR/admin-dashboards.pid"

# shellcheck source=scripts/local-ports.sh
source "$ROOT_DIR/scripts/local-ports.sh"

if [[ -f "$PID_FILE" ]]; then
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    echo "Stopped admin dashboards (pid $pid)"
  fi
  rm -f "$PID_FILE"
fi

pkill -f "port-forward.*svc/keycloak.*${PAXO_KEYCLOAK_NODE_PORT}:8080" >/dev/null 2>&1 || true
pkill -f "port-forward.*svc/argocd-server.*${PAXO_ARGOCD_LOCAL_PORT}:80" >/dev/null 2>&1 || true
echo "Done."
