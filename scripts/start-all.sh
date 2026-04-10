#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.ngrok-runtime"

mkdir -p "$RUNTIME_DIR"

echo "Starting all microservices with local access..."
echo

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
    if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

require_cmd kubectl
require_cmd nc

# Clean up any stale processes
pkill -f "kubectl port-forward svc/paxo-frontend" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/keycloak" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/api-gateway" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/identity-service" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/product-management-service" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/jaeger" >/dev/null 2>&1 || true
pkill -f "ngrok" >/dev/null 2>&1 || true

# Verify services exist
for svc in paxo-frontend keycloak api-gateway identity-service product-management-service jaeger; do
  if ! kubectl get svc "$svc" >/dev/null 2>&1; then
    echo "Error: Service '$svc' not found in cluster." >&2
    exit 1
  fi
done

echo "Starting port forwards..."

# Frontend
nohup kubectl port-forward svc/paxo-frontend 4200:80 >"$RUNTIME_DIR/frontend.log" 2>&1 &
echo $! >"$RUNTIME_DIR/frontend.pid"
echo -n "  Frontend (4200)... "

# Keycloak
nohup kubectl port-forward svc/keycloak 8080:8080 >"$RUNTIME_DIR/keycloak.log" 2>&1 &
echo $! >"$RUNTIME_DIR/keycloak.pid"
echo -n "waiting"

# API Gateway
nohup kubectl port-forward svc/api-gateway 8085:8085 >"$RUNTIME_DIR/gateway.log" 2>&1 &
echo $! >"$RUNTIME_DIR/gateway.pid"

# Identity Service
nohup kubectl port-forward svc/identity-service 8087:8087 >"$RUNTIME_DIR/identity.log" 2>&1 &
echo $! >"$RUNTIME_DIR/identity.pid"

# Product Management Service
nohup kubectl port-forward svc/product-management-service 8088:8088 >"$RUNTIME_DIR/product.log" 2>&1 &
echo $! >"$RUNTIME_DIR/product.pid"

# Jaeger
nohup kubectl port-forward svc/jaeger 16686:16686 >"$RUNTIME_DIR/jaeger.log" 2>&1 &
echo $! >"$RUNTIME_DIR/jaeger.pid"

# Wait for all ports
for port in 4200 8080 8085 8087 8088 16686; do
  if wait_for_port "$port"; then
    echo -n "."
  else
    echo "Error: Port $port did not open in time." >&2
    exit 1
  fi
done

echo " done!"
echo

echo "=========================================="
echo "ALL SERVICES RUNNING - LOCAL ACCESS URLS"
echo "=========================================="
echo
echo "Frontend:               http://127.0.0.1:4200"
echo "Keycloak:               http://127.0.0.1:8080"
echo "Keycloak Admin:         http://127.0.0.1:8080/admin/master/console/"
echo "API Gateway:            http://127.0.0.1:8085"
echo "Identity Service:       http://127.0.0.1:8087"
echo "Product Service:        http://127.0.0.1:8088"
echo "Jaeger UI:              http://127.0.0.1:16686"
echo
echo "Keycloak OpenID Config: http://127.0.0.1:8080/realms/master/.well-known/openid-configuration"
echo
echo "Common API Paths:"
echo "  Signup:               http://127.0.0.1:4200/identity/signup"
echo "  Identity/Login:       http://127.0.0.1:4200/identity/{realm}/login"
echo "  Product Health:       http://127.0.0.1:4200/project/provision/health"
echo
echo "Stop all services:"
echo "  ./scripts/stop-all.sh"
echo
echo "=========================================="
