#!/usr/bin/env bash
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
  local retries=40
  for ((i=1; i<=retries; i++)); do
    # Match kubectl binding when --address localhost (127.0.0.1 and/or ::1)
    if nc -z localhost "$port" >/dev/null 2>&1 || nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "Error: timeout waiting for localhost:$port" >&2
  return 1
}

stop_if_running() {
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

start_resilient_forward() {
  local name="$1"
  local service="$2"
  local local_port="$3"
  local remote_port="$4"
  local log_file="$RUNTIME_DIR/$name.log"

  # The wrapper stays alive and restarts kubectl if port-forward exits because
  # of pod reschedules, apiserver reconnects, or laptop network/sleep events.
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
      printf "[%s] starting kubectl port-forward svc/%s %s:%s\n" "$(date -Is)" "$1" "$2" "$3"
      kubectl -n "$4" port-forward "svc/$1" "$2:$3" --address localhost &
      child=$!
      wait "$child"
      exit_code=$?
      child=""
      printf "[%s] port-forward svc/%s exited with code %s; restarting in 2s\n" "$(date -Is)" "$1" "$exit_code"
      sleep 2
    done
  ' _ "$service" "$local_port" "$remote_port" "$NS" >"$log_file" 2>&1 &

  echo $! >"$RUNTIME_DIR/$name.pid"
}

start_forward() {
  local name="$1"
  local service="$2"
  local local_port="$3"
  local remote_port="$4"

  stop_if_running "$name"
  pkill -f "kubectl.*port-forward.*svc/$service.*$local_port:$remote_port" >/dev/null 2>&1 || true

  start_resilient_forward "$name" "$service" "$local_port" "$remote_port"

  wait_for_port "$local_port"
}

require_cmd kubectl
require_cmd nc

# Ensure required services exist before attempting forwards.
for svc in paxo-frontend keycloak api-gateway identity-service product-management-service python-frontend jaeger; do
  if ! kubectl -n "$NS" get svc "$svc" >/dev/null 2>&1; then
    echo "Error: Kubernetes service '$svc' not found." >&2
    exit 1
  fi
done

start_forward "frontend" "paxo-frontend" "$PAXO_FRONTEND_LOCAL_PORT" 80
start_forward "keycloak" "keycloak" "$PAXO_KEYCLOAK_LOCAL_PORT" 8080
start_forward "gateway" "api-gateway" "$PAXO_GATEWAY_LOCAL_PORT" 8085
start_forward "identity" "identity-service" "$PAXO_IDENTITY_LOCAL_PORT" 8087
start_forward "product" "product-management-service" "$PAXO_PRODUCT_LOCAL_PORT" 8088
start_forward "python-frontend" "python-frontend" "$PAXO_PYTHON_FRONTEND_LOCAL_PORT" 80
start_forward "jaeger" "jaeger" "$PAXO_JAEGER_LOCAL_PORT" 16686

# Product UI frontends (NodePort → same port on localhost so "Open product" works).
echo
echo "Product frontend port-forwards (for catalog Open product links):"
while IFS=$'\t' read -r svc_name node_port; do
  [[ -z "${svc_name:-}" || -z "${node_port:-}" ]] && continue
  case "$svc_name" in
    paxo-frontend|python-frontend) continue ;;
  esac
  if [[ ! "$svc_name" =~ -frontend$ ]]; then
    continue
  fi
  forward_name="product-ui-${svc_name}"
  start_forward "$forward_name" "$svc_name" "$node_port" 80
  echo "  http://127.0.0.1:${node_port}/  →  svc/${svc_name}"
done < <(
  kubectl -n "$NS" get svc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.ports[0].nodePort}{"\n"}{end}' 2>/dev/null \
    | awk -F'\t' '$2 != "" && $2 != "0" && $2 != "<no value>"'
)

echo
echo "Local URLs (open in browser — localhost or 127.0.0.1 both work):"
echo "Frontend: http://localhost:${PAXO_FRONTEND_LOCAL_PORT}"
echo "Keycloak: http://localhost:${PAXO_KEYCLOAK_LOCAL_PORT}"
echo "Gateway: http://localhost:${PAXO_GATEWAY_LOCAL_PORT}"
echo "Identity: http://localhost:${PAXO_IDENTITY_LOCAL_PORT}"
echo "Product: http://localhost:${PAXO_PRODUCT_LOCAL_PORT}"
echo "Generate Product: http://localhost:${PAXO_PYTHON_FRONTEND_LOCAL_PORT}"
echo "Jaeger UI: http://localhost:${PAXO_JAEGER_LOCAL_PORT}"
echo
echo "Keycloak OpenID config: http://localhost:${PAXO_KEYCLOAK_LOCAL_PORT}/realms/master/.well-known/openid-configuration"
echo "Catalog Open product links use http://127.0.0.1:<nodePort>/ — requires the product UI forwards above."
echo "These forwards auto-restart if kubectl drops. Stop all forwards with: ./scripts/stop-local-access.sh"
