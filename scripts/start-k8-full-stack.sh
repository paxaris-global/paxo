#!/usr/bin/env bash
# Apply all Paxo Kubernetes manifests, refresh Argo CD, and wait for deployments.
# Run from anywhere:  ./scripts/start-k8-full-stack.sh   (from paxo repo root is typical)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K8_DIR="${ROOT_DIR}/k8"

# shellcheck source=scripts/local-ports.sh
source "$ROOT_DIR/scripts/local-ports.sh"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' is not installed." >&2
    exit 1
  fi
}

require_cmd kubectl

echo "==> Paxo full stack (Kubernetes + Argo CD)"
echo "    Repo root: ${ROOT_DIR}"
echo "    Manifests: ${K8_DIR}"
echo

if [[ ! -d "${K8_DIR}" ]]; then
  echo "Error: k8 directory not found: ${K8_DIR}" >&2
  exit 1
fi

echo "==> Applying all YAML under k8/ (recursive)..."
# -R applies nested dirs (e.g. k8/generated-apps/)
kubectl apply -R -f "${K8_DIR}"

echo
echo "==> Requesting Argo CD hard refresh for paxo-app..."
if kubectl -n argocd get application paxo-app >/dev/null 2>&1; then
  kubectl -n argocd patch application paxo-app --type merge \
    -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' || true
else
  echo "    (Application paxo-app not found in namespace argocd — skipped. Install Argo CD app if needed.)"
fi

echo
echo "==> Waiting for deployments in namespace default (timeout 10m each)..."
DEPLOY_COUNT=0
while IFS= read -r d; do
  [[ -z "$d" ]] && continue
  DEPLOY_COUNT=$((DEPLOY_COUNT + 1))
  echo "    rollout: $d"
  kubectl -n default rollout status "deployment/${d}" --timeout=600s
done < <(kubectl -n default get deploy -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
if [[ "$DEPLOY_COUNT" -eq 0 ]]; then
  echo "Warning: no deployments found in default. Check kubectl context and namespace." >&2
fi

echo
echo "==> Status"
kubectl -n argocd get applications.argoproj.io -o wide 2>/dev/null || true
echo
kubectl -n default get deploy -o wide 2>/dev/null || true

echo
echo "Done. Full stack applied and rollouts completed."
echo "Local UI (optional): kubectl -n default port-forward svc/paxo-frontend ${PAXO_FRONTEND_LOCAL_PORT}:80 --address 127.0.0.1"
echo "Argo UI (optional):  ./scripts/start-argocd-ui.sh"
