#!/usr/bin/env bash
# One-shot: make Argo CD UI work on Minikube (HTTP, no TLS redirect loop).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_PORT="${ARGOCD_LOCAL_PORT:-8081}"

if ! kubectl get ns argocd >/dev/null 2>&1; then
  echo "Error: Argo CD namespace 'argocd' not found. Install Argo CD first." >&2
  exit 1
fi

echo "==> Enabling Argo CD server.insecure (HTTP for local port-forward)"
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"server.insecure":"true"}}' 2>/dev/null || \
  kubectl -n argocd create configmap argocd-cmd-params-cm \
    --from-literal=server.insecure=true \
    -o yaml --dry-run=client | kubectl apply -f -

echo "==> Setting public UI URL"
kubectl -n argocd patch configmap argocd-cm --type merge \
  -p "{\"data\":{\"url\":\"http://127.0.0.1:${LOCAL_PORT}\"}}"

echo "==> Restarting argocd-server"
kubectl -n argocd rollout restart deployment argocd-server
kubectl -n argocd rollout status deployment argocd-server --timeout=120s

echo "==> Stopping crash-looping ApplicationSet controller (optional CRD missing on this install)"
kubectl -n argocd scale deployment argocd-applicationset-controller --replicas=0 2>/dev/null || true

"${ROOT_DIR}/scripts/start-argocd-ui.sh"

echo
echo "Health check:"
curl -sf "http://127.0.0.1:${LOCAL_PORT}/healthz" && echo " OK" || echo " FAILED — check ${ROOT_DIR}/.ngrok-runtime/argocd-ui.log"
