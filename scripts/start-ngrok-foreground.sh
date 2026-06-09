#!/usr/bin/env bash
# Keep paxo-frontend port-forward + ngrok alive (used by start-ngrok.sh).
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.ngrok-runtime"
NGROK_CONFIG="$ROOT_DIR/ngrok/ngrok.yml"
NGROK_SYSTEM_CONFIG="${HOME}/Library/Application Support/ngrok/ngrok.yml"
NS="${KUBECTL_NAMESPACE:-default}"

# shellcheck source=scripts/local-ports.sh
source "$ROOT_DIR/scripts/local-ports.sh"

LOCAL_PORT="$PAXO_FRONTEND_LOCAL_PORT"
CUSTOM_DOMAIN="${NGROK_CUSTOM_DOMAIN:-}"

mkdir -p "$RUNTIME_DIR"

wait_for_port() {
  local port="$1"
  for ((i = 1; i <= 60; i++)); do
    if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

PIDS=()
cleanup() {
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  exit 0
}
trap cleanup TERM INT

kubectl -n "$NS" port-forward "svc/paxo-frontend" "${LOCAL_PORT}:80" --address 127.0.0.1 &
pf_pid=$!
PIDS+=("$pf_pid")
echo "port-forward svc/paxo-frontend -> 127.0.0.1:${LOCAL_PORT} (pid ${pf_pid})"

if ! wait_for_port "$LOCAL_PORT"; then
  echo "Error: paxo-frontend port-forward did not open ${LOCAL_PORT}" >&2
  exit 1
fi

NGROK_ARGS=(http "$LOCAL_PORT")
if [[ -f "$NGROK_SYSTEM_CONFIG" ]]; then
  NGROK_ARGS+=(--config "$NGROK_SYSTEM_CONFIG")
fi
if [[ -f "$NGROK_CONFIG" ]]; then
  NGROK_ARGS+=(--config "$NGROK_CONFIG")
fi
if [[ -n "$CUSTOM_DOMAIN" ]]; then
  NGROK_ARGS+=(--domain="$CUSTOM_DOMAIN")
fi

ngrok "${NGROK_ARGS[@]}" &
ngrok_pid=$!
PIDS+=("$ngrok_pid")
echo "ngrok tunnel (pid ${ngrok_pid})"

wait
