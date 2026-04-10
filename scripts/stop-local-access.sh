#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.local-runtime"

stop_if_running() {
  local name="$1"
  if [[ -f "$RUNTIME_DIR/$name.pid" ]]; then
    local pid
    pid="$(cat "$RUNTIME_DIR/$name.pid" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      echo "Stopped $name (pid $pid)"
    fi
    rm -f "$RUNTIME_DIR/$name.pid"
  fi
}

mkdir -p "$RUNTIME_DIR"

stop_if_running "frontend"
stop_if_running "keycloak"
stop_if_running "gateway"
stop_if_running "identity"
stop_if_running "product"
stop_if_running "jaeger"

# Extra cleanup if stale forwards exist without pid files.
pkill -f "kubectl port-forward svc/paxo-frontend 4200:80" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/keycloak 8080:8080" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/api-gateway 8085:8085" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/identity-service 8087:8087" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/product-management-service 8088:8088" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/jaeger 16686:16686" >/dev/null 2>&1 || true

echo "All local forwards stopped."
