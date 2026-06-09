#!/usr/bin/env bash
# Access Argo-deployed pods via localhost on the same ports as Kubernetes NodePorts.
# No ng serve — traffic goes to in-cluster Services (paxo-frontend, api-gateway, …).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.local-runtime"
NS="${KUBECTL_NAMESPACE:-default}"

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

stop_forward() {
  local name="$1"
  if [[ -f "$RUNTIME_DIR/$name.pid" ]]; then
    local pid
    pid="$(cat "$RUNTIME_DIR/$name.pid" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$RUNTIME_DIR/$name.pid"
  fi
}

start_nodeport_forward() {
  local name="$1"
  local service="$2"
  local node_port="$3"
  local remote_port="$4"
  local log_file="$RUNTIME_DIR/$name.log"

  stop_forward "$name"
  pkill -f "kubectl.*port-forward.*svc/${service}.*${node_port}:${remote_port}" >/dev/null 2>&1 || true

  nohup bash -c '
    set -u
    child=""
    ts() { date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date; }
    trap "" HUP
    while true; do
      printf "[%s] nodeport-forward svc/%s %s:%s\n" "$(ts)" "$1" "$2" "$3"
      kubectl -n "$4" port-forward "svc/$1" "$2:$3" --address 127.0.0.1 &
      child=$!
      wait "$child" || true
      child=""
      sleep 2
    done
  ' _ "$service" "$node_port" "$remote_port" "$NS" >"$log_file" 2>&1 &
  local wrapper_pid=$!
  disown -h "$wrapper_pid" 2>/dev/null || true
  echo "$wrapper_pid" >"$RUNTIME_DIR/$name.pid"
  wait_for_port "$node_port"
}

require_cmd kubectl
require_cmd nc

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "Error: Kubernetes cluster not reachable. Is Minikube running?" >&2
  exit 1
fi

# Stop legacy dev ports (4200, 8085, …) and any old tunnel attempt.
"$ROOT_DIR/scripts/stop-local-access.sh" >/dev/null 2>&1 || true
"$ROOT_DIR/scripts/stop-minikube-access.sh" >/dev/null 2>&1 || true
pkill -f "kubectl.*port-forward" >/dev/null 2>&1 || true
sleep 1

for svc in paxo-frontend keycloak api-gateway identity-service product-management-service python-foundry-api python-frontend jaeger; do
  if ! kubectl -n "$NS" get svc "$svc" >/dev/null 2>&1; then
    echo "Error: service '$svc' not found in namespace $NS" >&2
    exit 1
  fi
done

echo "Binding localhost to Kubernetes NodePorts (cluster Services via kubectl)…"

start_nodeport_forward "np-frontend" "paxo-frontend" "$PAXO_FRONTEND_NODE_PORT" 80
start_nodeport_forward "np-keycloak" "keycloak" "$PAXO_KEYCLOAK_NODE_PORT" 8080
start_nodeport_forward "np-gateway" "api-gateway" "$PAXO_GATEWAY_NODE_PORT" 8085
start_nodeport_forward "np-identity" "identity-service" 32087 8087
start_nodeport_forward "np-product" "product-management-service" 32088 8088
start_nodeport_forward "np-python-api" "python-foundry-api" 32090 8000
start_nodeport_forward "np-python-ui" "python-frontend" 32081 80
start_nodeport_forward "np-jaeger" "jaeger" 31686 16686

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
echo "Logs: $RUNTIME_DIR/np-*.log"
echo "Stop: $ROOT_DIR/scripts/stop-minikube-access.sh"
