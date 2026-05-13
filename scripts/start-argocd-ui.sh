#!/usr/bin/env bash
# Port-forward Argo CD UI to localhost. Uses HTTP (service port 80) when the cluster has
# server.insecure=true — no Chrome TLS warnings for local dev.
#
# Prerequisites (applied once on the cluster):
#   kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
#     -p '{"data":{"server.insecure":"true"}}'
#   kubectl -n argocd patch configmap argocd-cm --type merge \
#     -p '{"data":{"url":"http://127.0.0.1:'"${ARGOCD_LOCAL_PORT:-8081}"'"}}'
#   kubectl -n argocd rollout restart deployment argocd-server
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
    if nc -z localhost "$port" >/dev/null 2>&1 || nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
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

# Stop prior forwards (HTTP :80 or legacy HTTPS :443)
if [[ -f "$RUNTIME_DIR/argocd-ui.pid" ]]; then
  old_pid="$(cat "$RUNTIME_DIR/argocd-ui.pid" 2>/dev/null || true)"
  if [[ -n "${old_pid:-}" ]] && kill -0 "$old_pid" >/dev/null 2>&1; then
    kill "$old_pid" >/dev/null 2>&1 || true
  fi
  rm -f "$RUNTIME_DIR/argocd-ui.pid"
fi
pkill -f "port-forward.*svc/argocd-server.*${LOCAL_PORT}:80" >/dev/null 2>&1 || true
pkill -f "port-forward.*svc/argocd-server.*${LOCAL_PORT}:443" >/dev/null 2>&1 || true

echo "Starting Argo CD UI port-forward (HTTP): http://127.0.0.1:${LOCAL_PORT}"
echo "        Open this exact URL in Chrome — no certificate warning."
nohup bash -c '
  set -u
  child=""
  cleanup() {
    if [[ -n "${child:-}" ]] && kill -0 "$child" >/dev/null 2>&1; then
      kill "$child" >/dev/null 2>&1 || true
      wait "$child" >/dev/null 2>&1 || true
    fi
    exit 0
  }
  trap cleanup TERM INT EXIT

  while true; do
    printf "[%s] starting kubectl port-forward svc/argocd-server %s:80\n" "$(date -Is)" "$1"
    kubectl -n argocd port-forward svc/argocd-server "$1:80" --address localhost &
    child=$!
    wait "$child"
    exit_code=$?
    child=""
    printf "[%s] argocd-server port-forward exited with code %s; restarting in 2s\n" "$(date -Is)" "$exit_code"
    sleep 2
  done
' _ "$LOCAL_PORT" >"$RUNTIME_DIR/argocd-ui.log" 2>&1 &
echo $! >"$RUNTIME_DIR/argocd-ui.pid"

if ! wait_for_port "$LOCAL_PORT"; then
  echo "Error: port ${LOCAL_PORT} did not open. Log:" >&2
  tail -n 30 "$RUNTIME_DIR/argocd-ui.log" >&2 || true
  exit 1
fi

echo
echo "Argo CD UI:  http://127.0.0.1:${LOCAL_PORT}  (or http://localhost:${LOCAL_PORT})"
echo "If the UI shows \"Unable to load data\", run:"
echo "  ARGOCD_UI_URL=http://127.0.0.1:${LOCAL_PORT} ./scripts/patch-argocd-ui-url.sh"
echo "Username: admin"
echo "Password: run ./scripts/print-argocd-admin-password.sh"
echo "Auto-restarts if kubectl drops. Stop: ./scripts/stop-argocd-ui.sh"
