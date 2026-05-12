#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.ngrok-runtime"
LOCAL_PORT="${ARGOCD_LOCAL_PORT:-8081}"

mkdir -p "$RUNTIME_DIR"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' is not installed." >&2
    exit 1
  fi
}

wait_for_port() {
  local port="$1"
  local retries=40
  for ((i = 1; i <= retries; i++)); do
    if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

require_cmd kubectl
require_cmd nc

if ! kubectl get ns argocd >/dev/null 2>&1; then
  echo "Error: namespace 'argocd' not found. Install Argo CD first." >&2
  exit 1
fi
if ! kubectl -n argocd get svc argocd-server >/dev/null 2>&1; then
  echo "Error: service argocd-server not found in argocd namespace." >&2
  exit 1
fi

pkill -f "port-forward.*svc/argocd-server.*${LOCAL_PORT}:443" >/dev/null 2>&1 || true

echo "Starting Argo CD UI port-forward: https://127.0.0.1:${LOCAL_PORT} (insecure / self-signed TLS is normal)"
nohup kubectl -n argocd port-forward svc/argocd-server "${LOCAL_PORT}:443" --address 127.0.0.1 \
  >"$RUNTIME_DIR/argocd-ui.log" 2>&1 &
echo $! >"$RUNTIME_DIR/argocd-ui.pid"

if ! wait_for_port "$LOCAL_PORT"; then
  echo "Error: port ${LOCAL_PORT} did not open. Log:" >&2
  tail -n 30 "$RUNTIME_DIR/argocd-ui.log" >&2 || true
  exit 1
fi

echo "Argo CD UI is available at https://127.0.0.1:${LOCAL_PORT}"
echo "Username: admin"
echo "Password: run ./scripts/print-argocd-admin-password.sh"
echo "Stop:       ./scripts/stop-argocd-ui.sh"
