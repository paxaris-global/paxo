#!/usr/bin/env bash
set -euo pipefail

LOCAL_PORT="${ARGOCD_LOCAL_PORT:-8081}"

pkill -f "port-forward.*svc/argocd-server.*${LOCAL_PORT}:443" >/dev/null 2>&1 || true

echo "Argo CD UI port-forward (port ${LOCAL_PORT}) stopped (if it was running)."
