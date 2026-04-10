#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.ngrok-runtime"
NGROK_SYSTEM_CONFIG="${HOME}/Library/Application Support/ngrok/ngrok.yml"

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
  return 1
}

require_cmd ngrok
require_cmd nc

# Start ngrok for frontend (exposes all services via frontend proxy)
echo "Starting ngrok for public access..."
echo

nohup ngrok http 4200 --config "$NGROK_SYSTEM_CONFIG" >"$RUNTIME_DIR/ngrok-public.log" 2>&1 &
echo $! >"$RUNTIME_DIR/ngrok-public.pid"

if ! wait_for_port 4040; then
  echo "Error: ngrok did not start." >&2
  tail -n 40 "$RUNTIME_DIR/ngrok-public.log" >&2 || true
  exit 1
fi

# Get the public URL
PUBLIC_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | python3 -c 'import sys,json;d=json.load(sys.stdin);ts=d.get("tunnels",[]);url=ts[0]["public_url"] if ts else "";print(url)')

if [[ -z "$PUBLIC_URL" ]]; then
  echo "Error: Could not get public URL from ngrok." >&2
  tail -n 40 "$RUNTIME_DIR/ngrok-public.log" >&2 || true
  exit 1
fi

echo "=========================================="
echo "ALL SERVICES RUNNING - PUBLIC ACCESS"
echo "=========================================="
echo
echo "Base URL: $PUBLIC_URL"
echo
echo "Frontend:               $PUBLIC_URL"
echo "Signup:                 $PUBLIC_URL/identity/signup"
echo "Login:                  $PUBLIC_URL/identity/{realm}/login"
echo "Product Health:         $PUBLIC_URL/project/provision/health"
echo "Gateway Health:         $PUBLIC_URL/gateway/actuator/health"
echo
echo "To also expose Keycloak publicly in a separate terminal:"
echo "  cd paxo && ./scripts/start-ngrok.sh keycloak"
echo
echo "To stop public access:"
echo "  ./scripts/stop-public.sh"
echo
echo "=========================================="
