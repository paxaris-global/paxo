#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.local-runtime"

for pid_file in "$RUNTIME_DIR"/np-*.pid "$RUNTIME_DIR"/minikube-tunnel.pid; do
  [[ -e "$pid_file" ]] || continue
  pid="$(cat "$pid_file" 2>/dev/null || true)"
  if [[ -n "${pid:-}" ]] && kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
    echo "Stopped $(basename "$pid_file" .pid) (pid $pid)"
  fi
  rm -f "$pid_file"
done

pkill -f "kubectl.*port-forward.*--address 127.0.0.1" >/dev/null 2>&1 || true
pkill -f "minikube tunnel" >/dev/null 2>&1 || true
echo "NodePort access stopped."
