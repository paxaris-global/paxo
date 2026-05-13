#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.ngrok-runtime"

stop_from_pid_file() {
  local name="$1"
  local file="$RUNTIME_DIR/$name.pid"

  if [[ -f "$file" ]]; then
    local pid
    pid="$(cat "$file" 2>/dev/null || true)"
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
      echo "Stopped $name (PID $pid)"
    fi
    rm -f "$file"
  fi
}

stop_from_pid_file "ngrok"
stop_from_pid_file "port-forward-frontend"
stop_from_pid_file "port-forward-keycloak"

# Best-effort cleanup for stale processes not tracked by PID files.
pkill -f "ngrok start --all" >/dev/null 2>&1 || true
pkill -f "ngrok http" >/dev/null 2>&1 || true
pkill -f "kubectl.*port-forward.*svc/paxo-frontend" >/dev/null 2>&1 || true
pkill -f "kubectl.*port-forward.*svc/keycloak" >/dev/null 2>&1 || true

echo "Done."
