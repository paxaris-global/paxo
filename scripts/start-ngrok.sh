#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.ngrok-runtime"
FOREGROUND_SCRIPT="$ROOT_DIR/scripts/start-ngrok-foreground.sh"
DOMAIN_SUFFIX="${NGROK_DOMAIN_SUFFIX:-ngrok-free.app}"
NS="${KUBECTL_NAMESPACE:-default}"

# shellcheck source=scripts/local-ports.sh
source "$ROOT_DIR/scripts/local-ports.sh"

TARGET_INPUT="${1:-frontend}"
CUSTOM_DOMAIN_INPUT="${2:-}"

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
    if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "Error: timeout waiting for localhost:$port" >&2
  return 1
}

stop_if_running() {
  if [[ -f "$RUNTIME_DIR/$1.pid" ]]; then
    local pid
    pid="$(cat "$RUNTIME_DIR/$1.pid" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
    rm -f "$RUNTIME_DIR/$1.pid"
  fi
}

require_cmd kubectl
require_cmd ngrok
require_cmd nc
require_cmd curl

if [[ "$TARGET_INPUT" == "keycloak" ]]; then
  echo "Error: use start-ngrok.sh for frontend only; Keycloak is reached via nginx /identity." >&2
  exit 1
fi

if ! kubectl -n "$NS" get svc paxo-frontend >/dev/null 2>&1; then
  echo "Error: Kubernetes service 'paxo-frontend' not found." >&2
  exit 1
fi

"$ROOT_DIR/scripts/stop-minikube-access.sh" >/dev/null 2>&1 || true
"$ROOT_DIR/scripts/stop-local-access.sh" >/dev/null 2>&1 || true
"$ROOT_DIR/scripts/stop-ngrok.sh" >/dev/null 2>&1 || true
pkill -f "kubectl.*port-forward" >/dev/null 2>&1 || true
sleep 1

export NGROK_CUSTOM_DOMAIN=""
if [[ -n "$CUSTOM_DOMAIN_INPUT" ]]; then
  if [[ "$CUSTOM_DOMAIN_INPUT" == *.* ]]; then
    export NGROK_CUSTOM_DOMAIN="$CUSTOM_DOMAIN_INPUT"
  else
    export NGROK_CUSTOM_DOMAIN="$CUSTOM_DOMAIN_INPUT.$DOMAIN_SUFFIX"
  fi
elif [[ -n "$TARGET_INPUT" && "$TARGET_INPUT" != "frontend" ]]; then
  if [[ "$TARGET_INPUT" == *.* ]]; then
    export NGROK_CUSTOM_DOMAIN="$TARGET_INPUT"
  else
    export NGROK_CUSTOM_DOMAIN="$TARGET_INPUT.$DOMAIN_SUFFIX"
  fi
fi

chmod +x "$FOREGROUND_SCRIPT"
nohup "$FOREGROUND_SCRIPT" >>"$RUNTIME_DIR/ngrok-foreground.log" 2>&1 &
echo $! >"$RUNTIME_DIR/ngrok-foreground.pid"
disown -h "$(cat "$RUNTIME_DIR/ngrok-foreground.pid")" 2>/dev/null || true

wait_for_port "$PAXO_FRONTEND_LOCAL_PORT"
for ((i = 1; i <= 30; i++)); do
  if nc -z 127.0.0.1 4040 >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if ! nc -z 127.0.0.1 4040 >/dev/null 2>&1; then
  echo "Error: ngrok admin API (4040) not ready. See $RUNTIME_DIR/ngrok-foreground.log" >&2
  tail -n 30 "$RUNTIME_DIR/ngrok-foreground.log" >&2 || true
  exit 1
fi
sleep 2

echo
echo "Local endpoints:"
echo "  Frontend:    http://127.0.0.1:$PAXO_FRONTEND_LOCAL_PORT"
echo

if [[ -n "$NGROK_CUSTOM_DOMAIN" ]]; then
  echo "Requested domain:"
  echo "  https://$NGROK_CUSTOM_DOMAIN"
  echo
fi

echo "Public ngrok tunnels:"
if command -v jq >/dev/null 2>&1; then
  TUNNELS_OUTPUT="$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[] | "  " + (.name // "tunnel") + ": " + .public_url')"
else
  TUNNELS_OUTPUT="$(curl -s http://127.0.0.1:4040/api/tunnels | grep -o '"public_url":"[^"]*"' | sed 's/"public_url":"/  /;s/"$//')"
fi

if [[ -n "$TUNNELS_OUTPUT" ]]; then
  echo "$TUNNELS_OUTPUT"
else
  echo "  (no active tunnels reported)"
  tail -n 40 "$RUNTIME_DIR/ngrok-foreground.log" >&2 || true
  exit 1
fi

NGROK_PUBLIC_URL=""
if command -v jq >/dev/null 2>&1; then
  NGROK_PUBLIC_URL="$(curl -s http://127.0.0.1:4040/api/tunnels \
    | jq -r '[.tunnels[] | select(.public_url | startswith("https://")) | .public_url][0] // empty')"
  if [[ -z "$NGROK_PUBLIC_URL" ]]; then
    NGROK_PUBLIC_URL="$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[0].public_url // empty')"
  fi
else
  NGROK_PUBLIC_URL="$(curl -s http://127.0.0.1:4040/api/tunnels \
    | grep -o '"public_url":"https://[^"]*"' | head -1 | sed 's/"public_url":"//;s/"$//')"
fi

if [[ -z "$NGROK_PUBLIC_URL" ]]; then
  echo "Warning: could not detect ngrok public URL." >&2
else
  NGROK_PUBLIC_URL="${NGROK_PUBLIC_URL%/}"
  echo "$NGROK_PUBLIC_URL" >"$RUNTIME_DIR/public-url.txt"
  echo
  echo "Updating product-management-service PROVISIONING_PAXO_PUBLIC_BASE_URL…"
  kubectl -n "$NS" set env deployment/product-management-service \
    "PROVISIONING_PAXO_PUBLIC_BASE_URL=${NGROK_PUBLIC_URL}" >/dev/null
  kubectl -n "$NS" rollout status deployment/product-management-service --timeout=120s >/dev/null
  echo "  PROVISIONING_PAXO_PUBLIC_BASE_URL=${NGROK_PUBLIC_URL}"
  echo
  echo "Open Paxo:        ${NGROK_PUBLIC_URL}/"
  echo "Open product:     ${NGROK_PUBLIC_URL}/product-ui/{realm}/{product-id}/"
  echo "Example:"
  echo "  ${NGROK_PUBLIC_URL}/product-ui/paxarisglobal/fashion-ecommerse-website/"
fi

echo
echo "Logs: $RUNTIME_DIR/ngrok-foreground.log"
echo "Stop: ./scripts/stop-ngrok.sh"
