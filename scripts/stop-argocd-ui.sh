#!/usr/bin/env bash
set -euo pipefail

LOCAL_PORT="${ARGOCD_LOCAL_PORT:-8081}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.ngrok-runtime"

if [[ -f "$RUNTIME_DIR/argocd-ui.pid" ]]; then
  pid="$(cat "$RUNTIME_DIR/argocd-ui.pid" 2>/dev/null || true)"
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
  fi
  rm -f "$RUNTIME_DIR/argocd-ui.pid"
fi

pkill -f "port-forward.*svc/argocd-server.*${LOCAL_PORT}:80" >/dev/null 2>&1 || true
pkill -f "port-forward.*svc/argocd-server.*${LOCAL_PORT}:443" >/dev/null 2>&1 || true

echo "Argo CD UI port-forward (port ${LOCAL_PORT}) stopped (if it was running)."
