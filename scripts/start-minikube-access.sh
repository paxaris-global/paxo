#!/usr/bin/env bash
# Start NodePort-aligned access to Argo-deployed Services (see start-minikube-access-foreground.sh).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.local-runtime"
FOREGROUND_SCRIPT="$ROOT_DIR/scripts/start-minikube-access-foreground.sh"
DAEMON_LOG="$RUNTIME_DIR/minikube-access-foreground.log"
PID_FILE="$RUNTIME_DIR/minikube-access-foreground.pid"

# shellcheck source=scripts/local-ports.sh
source "$ROOT_DIR/scripts/local-ports.sh"

mkdir -p "$RUNTIME_DIR"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' is not installed." >&2
    exit 1
  fi
}

wait_for_port() {
  local port="$1"
  for ((i = 1; i <= 40; i++)); do
    if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "Error: timeout waiting for 127.0.0.1:$port" >&2
  return 1
}

require_cmd kubectl
require_cmd nc

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "Error: Kubernetes cluster not reachable. Is Minikube running?" >&2
  exit 1
fi

"$ROOT_DIR/scripts/stop-local-access.sh" >/dev/null 2>&1 || true
"$ROOT_DIR/scripts/stop-minikube-access.sh" >/dev/null 2>&1 || true
pkill -f "kubectl.*port-forward" >/dev/null 2>&1 || true
sleep 1

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "${old_pid:-}" ]] && kill -0 "$old_pid" >/dev/null 2>&1; then
    echo "NodePort access already running (pid $old_pid)"
  else
    rm -f "$PID_FILE"
  fi
fi

if [[ ! -f "$PID_FILE" ]]; then
  echo "Starting NodePort forwards to Kubernetes Services…"
  chmod +x "$FOREGROUND_SCRIPT"
  nohup "$FOREGROUND_SCRIPT" >>"$DAEMON_LOG" 2>&1 &
  echo $! >"$PID_FILE"
  disown -h "$(cat "$PID_FILE")" 2>/dev/null || true
fi

wait_for_port "$PAXO_FRONTEND_NODE_PORT"

FRONTEND_URL="http://127.0.0.1:${PAXO_FRONTEND_NODE_PORT}"

echo
echo "=== Paxo (Kubernetes / Argo CD — no ng serve) ==="
echo "Paxo UI:          ${FRONTEND_URL}"
echo "API Gateway:      http://127.0.0.1:${PAXO_GATEWAY_NODE_PORT}"
echo "Keycloak:         http://127.0.0.1:${PAXO_KEYCLOAK_NODE_PORT}"
echo "Product API:      http://127.0.0.1:32088"
echo "Python Foundry:   http://127.0.0.1:32081"
echo "Jaeger:           http://127.0.0.1:31686"
echo
echo "Open product:     ${FRONTEND_URL}/product-ui/{realm}/{product}/"
echo
echo "Logs: $DAEMON_LOG"
echo "Stop: $ROOT_DIR/scripts/stop-minikube-access.sh"
echo "Or run in a terminal tab: $FOREGROUND_SCRIPT"
