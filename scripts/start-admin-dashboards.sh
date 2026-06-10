#!/usr/bin/env bash
# Keycloak + Argo CD local dashboards while ngrok / Paxo frontend keeps running.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.local-runtime"
PID_FILE="$RUNTIME_DIR/admin-dashboards.pid"
LOG_FILE="$RUNTIME_DIR/admin-dashboards.log"

# shellcheck source=scripts/local-ports.sh
source "$ROOT_DIR/scripts/local-ports.sh"

KEYCLOAK_LOCAL_PORT="${PAXO_KEYCLOAK_NODE_PORT}"
ARGOCD_LOCAL_PORT="${PAXO_ARGOCD_LOCAL_PORT}"

mkdir -p "$RUNTIME_DIR"

print_urls() {
  echo "Keycloak admin:  http://localhost:${KEYCLOAK_LOCAL_PORT}/admin/"
  echo "                 login admin / admin@123"
  echo
  echo "Argo CD UI:       http://127.0.0.1:${ARGOCD_LOCAL_PORT}"
  echo "                 login admin / run ./scripts/print-argocd-admin-password.sh"
  echo
  echo "Open in Chrome:   ./scripts/open-admin-dashboards.sh"
  echo "Paxo (ngrok):     your ngrok URL (separate from these local dashboards)"
  echo "Stop dashboards:  ./scripts/stop-admin-dashboards.sh"
  echo "Log:              ${LOG_FILE}"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' is not installed." >&2
    exit 1
  fi
}

dashboards_ports_ready() {
  nc -z 127.0.0.1 "$KEYCLOAK_LOCAL_PORT" >/dev/null 2>&1 \
    && nc -z 127.0.0.1 "$ARGOCD_LOCAL_PORT" >/dev/null 2>&1
}

require_cmd kubectl
require_cmd nc

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "Error: kubectl cannot reach the cluster (is minikube running?)." >&2
  exit 1
fi

if dashboards_ports_ready; then
  echo "Admin dashboards already reachable."
  echo
  print_urls
  exit 0
fi

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "${old_pid:-}" ]] && kill -0 "$old_pid" >/dev/null 2>&1; then
    kill "$old_pid" >/dev/null 2>&1 || true
    sleep 1
  fi
  rm -f "$PID_FILE"
fi

if kubectl get ns argocd >/dev/null 2>&1; then
  echo "==> Configuring Argo CD for local HTTP UI"
  kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
    -p '{"data":{"server.insecure":"true"}}' 2>/dev/null || \
  kubectl -n argocd create configmap argocd-cmd-params-cm \
    --from-literal=server.insecure=true \
    -o yaml --dry-run=client | kubectl apply -f -
  kubectl -n argocd patch configmap argocd-cm --type merge \
    -p "{\"data\":{\"url\":\"http://127.0.0.1:${ARGOCD_LOCAL_PORT}\"}}" >/dev/null
  kubectl -n argocd rollout restart deployment argocd-server >/dev/null 2>&1 || true
  kubectl -n argocd rollout status deployment argocd-server --timeout=120s >/dev/null 2>&1 || true
fi

nohup bash -c '
  set -u
  kc_child=""
  argo_child=""
  cleanup() {
    [[ -n "${kc_child:-}" ]] && kill "$kc_child" 2>/dev/null || true
    [[ -n "${argo_child:-}" ]] && kill "$argo_child" 2>/dev/null || true
    exit 0
  }
  trap cleanup TERM INT EXIT

  forward_loop() {
    local ns="$1" svc="$2" local_port="$3" remote_port="$4" label="$5"
    while true; do
      echo "[$(date "+%Y-%m-%dT%H:%M:%S")] starting $label port-forward ${local_port}:${remote_port}"
      kubectl -n "$ns" port-forward "svc/$svc" "${local_port}:${remote_port}" --address 127.0.0.1
      echo "[$(date "+%Y-%m-%dT%H:%M:%S")] $label port-forward exited; retry in 2s"
      sleep 2
    done
  }

  forward_loop default keycloak "$1" 8080 keycloak &
  kc_child=$!
  forward_loop argocd argocd-server "$2" 80 argocd &
  argo_child=$!
  wait
' _ "$KEYCLOAK_LOCAL_PORT" "$ARGOCD_LOCAL_PORT" >"$LOG_FILE" 2>&1 &
echo $! >"$PID_FILE"
disown -h "$(cat "$PID_FILE")" 2>/dev/null || true

for ((i = 1; i <= 45; i++)); do
  if dashboards_ports_ready; then
    break
  fi
  sleep 1
done

if ! dashboards_ports_ready; then
  echo "Error: dashboards did not open. Log:" >&2
  tail -n 20 "$LOG_FILE" >&2 || true
  exit 1
fi

echo
print_urls
