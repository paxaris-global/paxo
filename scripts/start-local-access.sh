#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.local-runtime"
NS="${KUBECTL_NAMESPACE:-default}"

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

start_forward() {
  local name="$1"
  local service="$2"
  local local_port="$3"
  local remote_port="$4"

  stop_if_running "$name"

  # "localhost" binds 127.0.0.1 + ::1 so http://localhost:4200 works (not only 127.0.0.1).
  nohup kubectl -n "$NS" port-forward "svc/$service" "$local_port:$remote_port" --address localhost >"$RUNTIME_DIR/$name.log" 2>&1 &
  echo $! >"$RUNTIME_DIR/$name.pid"

  wait_for_port "$local_port"
}

require_cmd kubectl
require_cmd nc

# Ensure required services exist before attempting forwards.
for svc in paxo-frontend keycloak api-gateway identity-service product-management-service jaeger; do
  if ! kubectl -n "$NS" get svc "$svc" >/dev/null 2>&1; then
    echo "Error: Kubernetes service '$svc' not found." >&2
    exit 1
  fi
done

start_forward "frontend" "paxo-frontend" 4200 80
start_forward "keycloak" "keycloak" 8080 8080
start_forward "gateway" "api-gateway" 8085 8085
start_forward "identity" "identity-service" 8087 8087
start_forward "product" "product-management-service" 8088 8088
start_forward "jaeger" "jaeger" 16686 16686

echo
echo "Local URLs (open in browser — localhost or 127.0.0.1 both work):"
echo "Frontend: http://localhost:4200"
echo "Keycloak: http://localhost:8080"
echo "Gateway: http://localhost:8085"
echo "Identity: http://localhost:8087"
echo "Product: http://localhost:8088"
echo "Jaeger UI: http://localhost:16686"
echo
echo "Keycloak OpenID config: http://localhost:8080/realms/master/.well-known/openid-configuration"
echo "Stop all forwards with: ./scripts/stop-local-access.sh"
