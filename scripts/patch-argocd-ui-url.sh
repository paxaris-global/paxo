#!/usr/bin/env bash
# Fix Argo CD UI "Unable to load data / CORS / Request terminated" when using kubectl port-forward.
# Argo CD must know the exact external URL you open in the browser (scheme + host + port).
#
# Usage:
#   ./scripts/patch-argocd-ui-url.sh
#   ARGOCD_UI_URL=https://localhost:8081 ./scripts/patch-argocd-ui-url.sh
#
# Open the UI at exactly ARGOCD_UI_URL after running start-argocd-ui.sh (same host/port).
set -euo pipefail

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' is not installed." >&2
    exit 1
  fi
}

require_cmd kubectl

LOCAL_PORT="${ARGOCD_LOCAL_PORT:-8081}"
# Match start-argocd-ui.sh (HTTP port-forward to svc:80 when server.insecure=true).
ARGOCD_UI_URL="${ARGOCD_UI_URL:-http://127.0.0.1:${LOCAL_PORT}}"

if ! kubectl get ns argocd >/dev/null 2>&1; then
  echo "Error: namespace argocd not found." >&2
  exit 1
fi

echo "Setting argocd-cm data.url to: ${ARGOCD_UI_URL}"
kubectl -n argocd patch configmap argocd-cm --type merge -p "{\"data\":{\"url\":\"${ARGOCD_UI_URL}\"}}"

echo "Restarting argocd-server (needed for url to take effect)..."
kubectl -n argocd rollout restart deployment argocd-server
kubectl -n argocd rollout status deployment argocd-server --timeout=120s

echo "Done. Open Argo CD at exactly: ${ARGOCD_UI_URL}"
echo "If you still see errors, use the same hostname everywhere (127.0.0.1 vs localhost matters for CORS)."
