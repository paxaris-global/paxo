#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.ngrok-runtime"
NGROK_CONFIG="$ROOT_DIR/ngrok/ngrok.yml"
NGROK_SYSTEM_CONFIG="${HOME}/Library/Application Support/ngrok/ngrok.yml"
DOMAIN_SUFFIX="${NGROK_DOMAIN_SUFFIX:-ngrok-free.app}"

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

print_usage() {
  echo "Usage:" >&2
  echo "  ./scripts/start-ngrok.sh [frontend|keycloak] [custom-domain]" >&2
  echo >&2
  echo "Examples:" >&2
  echo "  ./scripts/start-ngrok.sh" >&2
  echo "  ./scripts/start-ngrok.sh frontend paxaris-global-main.ngrok-free.app" >&2
  echo "  ./scripts/start-ngrok.sh keycloak" >&2
}

require_cmd kubectl
require_cmd ngrok
require_cmd nc

if [[ ! -f "$NGROK_CONFIG" ]]; then
  echo "Error: ngrok config not found at $NGROK_CONFIG" >&2
  exit 1
fi

TARGET=""
SERVICE_NAME=""
LOCAL_PORT=""
REMOTE_PORT=""
DISPLAY_NAME=""

case "$TARGET_INPUT" in
  frontend)
    TARGET="frontend"
    SERVICE_NAME="paxo-frontend"
    LOCAL_PORT="4200"
    REMOTE_PORT="80"
    DISPLAY_NAME="Frontend"
    ;;
  keycloak)
    TARGET="keycloak"
    SERVICE_NAME="keycloak"
    LOCAL_PORT="8080"
    REMOTE_PORT="8080"
    DISPLAY_NAME="Keycloak"
    ;;
  "")
    TARGET="frontend"
    SERVICE_NAME="paxo-frontend"
    LOCAL_PORT="4200"
    REMOTE_PORT="80"
    DISPLAY_NAME="Frontend"
    ;;
  *)
    # Backward compatibility: first argument can still be domain.
    TARGET="frontend"
    SERVICE_NAME="paxo-frontend"
    LOCAL_PORT="4200"
    REMOTE_PORT="80"
    DISPLAY_NAME="Frontend"
    CUSTOM_DOMAIN_INPUT="$TARGET_INPUT"
    ;;
esac

if ! kubectl get svc "$SERVICE_NAME" >/dev/null 2>&1; then
  echo "Error: Kubernetes service '$SERVICE_NAME' not found." >&2
  exit 1
fi

# Stop stale background processes from previous runs.
stop_if_running "port-forward-frontend"
stop_if_running "port-forward-keycloak"
stop_if_running "ngrok"

nohup kubectl port-forward "svc/$SERVICE_NAME" "$LOCAL_PORT:$REMOTE_PORT" >"$RUNTIME_DIR/port-forward-$TARGET.log" 2>&1 &
echo $! >"$RUNTIME_DIR/port-forward-$TARGET.pid"

wait_for_port "$LOCAL_PORT"

CUSTOM_DOMAIN=""
if [[ -n "$CUSTOM_DOMAIN_INPUT" ]]; then
  if [[ "$CUSTOM_DOMAIN_INPUT" == *.* ]]; then
    CUSTOM_DOMAIN="$CUSTOM_DOMAIN_INPUT"
  else
    CUSTOM_DOMAIN="$CUSTOM_DOMAIN_INPUT.$DOMAIN_SUFFIX"
  fi
fi

if [[ -n "$CUSTOM_DOMAIN" ]]; then
  nohup ngrok http "$LOCAL_PORT" --domain="$CUSTOM_DOMAIN" \
    --config "$NGROK_SYSTEM_CONFIG" --config "$NGROK_CONFIG" \
    >"$RUNTIME_DIR/ngrok.log" 2>&1 &
else
  nohup ngrok http "$LOCAL_PORT" \
    --config "$NGROK_SYSTEM_CONFIG" --config "$NGROK_CONFIG" \
    >"$RUNTIME_DIR/ngrok.log" 2>&1 &
fi
echo $! >"$RUNTIME_DIR/ngrok.pid"

if ! wait_for_port 4040; then
  echo "Error: ngrok did not start correctly." >&2
  if grep -q "ERR_NGROK_4018" "$RUNTIME_DIR/ngrok.log" 2>/dev/null; then
    echo "ngrok authentication is required." >&2
    echo "Run: ngrok config add-authtoken <YOUR_NGROK_AUTHTOKEN>" >&2
  fi
  echo "--- ngrok log ---" >&2
  tail -n 40 "$RUNTIME_DIR/ngrok.log" >&2 || true
  exit 1
fi

echo
echo "Local endpoints:"
echo "  $DISPLAY_NAME:    http://127.0.0.1:$LOCAL_PORT"
echo

if [[ -n "$CUSTOM_DOMAIN" ]]; then
  echo "Requested domain:"
  echo "  https://$CUSTOM_DOMAIN"
  echo
fi

echo "Public ngrok tunnels:"
if command -v jq >/dev/null 2>&1; then
  TUNNELS_OUTPUT="$(curl -s http://127.0.0.1:4040/api/tunnels | jq -r '.tunnels[] | "  " + .name + ": " + .public_url')"
else
  TUNNELS_OUTPUT="$(curl -s http://127.0.0.1:4040/api/tunnels | grep -o '"public_url":"[^"]*"' | sed 's/"public_url":"/  /;s/"$//')"
fi

if [[ -n "$TUNNELS_OUTPUT" ]]; then
  echo "$TUNNELS_OUTPUT"
else
  echo "  (no active tunnels reported)"
  echo "--- ngrok log ---" >&2
  tail -n 40 "$RUNTIME_DIR/ngrok.log" >&2 || true
  exit 1
fi

echo
echo "Use './scripts/stop-ngrok.sh' to stop all ngrok/port-forward processes."
