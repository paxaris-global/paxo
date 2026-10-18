#!/usr/bin/env bash
# Give Colima + Minikube enough RAM/CPU for Paxo hybrid (Compose + Argo + 1–2 product apps).
#
# Target (16 GB Mac):
#   Colima:   10 GiB RAM, 6 CPUs
#   Minikube:  7 GiB RAM, 3 CPUs
#
# WARNING: recreates the Minikube cluster (apps/secrets in the cluster are wiped).
# Compose volumes (MySQL signup data) are kept.
#
# Usage:
#   ./scripts/resize-local-resources.sh
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
export PATH
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DOCKER_HOST="${DOCKER_HOST:-unix://${HOME}/.colima/default/docker.sock}"

COLIMA_MEM_GB="${COLIMA_MEM_GB:-10}"
COLIMA_CPU="${COLIMA_CPU:-6}"
MINIKUBE_MEM_MB="${MINIKUBE_MEM_MB:-7168}"
MINIKUBE_CPU="${MINIKUBE_CPU:-3}"

log() { echo "[resize $(date '+%H:%M:%S')] $*"; }

log "1/6 Stopping Colima (all Docker containers pause)"
colima stop || true

log "2/6 Starting Colima with ${COLIMA_MEM_GB}GiB / ${COLIMA_CPU} CPUs"
# Updates profile without wiping the VM disk/images when possible.
colima start --memory "$COLIMA_MEM_GB" --cpu "$COLIMA_CPU" --mount-type virtiofs
docker context use colima >/dev/null
docker info >/dev/null

log "3/6 Recreating Minikube with ${MINIKUBE_MEM_MB}MiB / ${MINIKUBE_CPU} CPUs (required to change memory)"
minikube delete || true
minikube start --driver=docker --memory="$MINIKUBE_MEM_MB" --cpus="$MINIKUBE_CPU"
kubectl get nodes

log "4/6 Installing Argo CD (new cluster)"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# Local UI over HTTP without TLS warnings
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"server.insecure":"true"}}' || true
kubectl -n argocd patch configmap argocd-cm --type merge \
  -p '{"data":{"url":"http://127.0.0.1:8081"}}' || true
kubectl -n argocd rollout restart deployment argocd-server || true
kubectl -n argocd rollout status deployment/argocd-server --timeout=300s || true

log "5/7 Restoring cluster secrets + root Argo app"
ENV_FILE="${PAXO_ENV_FILE:-$ROOT_DIR/.env}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "$ENV_FILE"
  set +a
  bash "$ROOT_DIR/scripts/sync-github-credentials.sh" || true
  if [[ -n "${DOCKER_USERNAME:-}" && -n "${DOCKER_PASSWORD:-}" ]]; then
    kubectl -n default create secret docker-registry dockerhub-secret \
      --docker-server=https://index.docker.io/v1/ \
      --docker-username="$DOCKER_USERNAME" \
      --docker-password="$DOCKER_PASSWORD" \
      --dry-run=client -o yaml | kubectl apply -f - || true
  fi
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    kubectl -n argocd create secret generic github-repo-creds \
      --from-literal=type=git \
      --from-literal=url=https://github.com/PaxarisGlobal \
      --from-literal=username=git \
      --from-literal=password="$GITHUB_TOKEN" \
      --dry-run=client -o yaml | kubectl apply -f - || true
    kubectl -n argocd label secret github-repo-creds argocd.argoproj.io/secret-type=repo-creds --overwrite || true
    kubectl -n argocd create secret generic github-repo-creds-lower \
      --from-literal=type=git \
      --from-literal=url=https://github.com/paxaris-global \
      --from-literal=username=git \
      --from-literal=password="$GITHUB_TOKEN" \
      --dry-run=client -o yaml | kubectl apply -f - || true
    kubectl -n argocd label secret github-repo-creds-lower argocd.argoproj.io/secret-type=repo-creds --overwrite || true
  fi
else
  log "WARN: $ENV_FILE missing — skip secret restore (Create Product / image pulls will fail)"
fi
# Hybrid local stack: do NOT apply k8/argocd-app.yaml (full k8 tree OOMs).
# product-apps watches k8/generated-apps on GitHub and registers child apps.
if [[ -f "$ROOT_DIR/k8/product-apps.yaml" ]]; then
  kubectl apply -n argocd -f "$ROOT_DIR/k8/product-apps.yaml" || true
fi
if ls "$ROOT_DIR"/k8/generated-apps/*-app.yaml >/dev/null 2>&1; then
  kubectl apply -n argocd -f "$ROOT_DIR/k8/generated-apps/" || true
fi

log "6/7 Bringing Compose signup stack back"
bash "$ROOT_DIR/scripts/ensure-local-signup-stack.sh" || true

log "7/7 Starting Argo CD UI on :8081"
bash "$ROOT_DIR/scripts/start-argocd-ui.sh" || true

echo
log "Done."
echo "  Colima:   $(colima list 2>/dev/null | awk 'NR==2{print $4,$5}')"
echo "  Minikube: $(minikube config get memory 2>/dev/null || true) MB (profile memory)"
docker inspect minikube --format '  Minikube container limit: {{.HostConfig.Memory}} bytes' 2>/dev/null || true
echo
echo "  Argo CD:  http://127.0.0.1:8081  (admin / ./scripts/print-argocd-admin-password.sh)"
echo "  Paxo UI:  http://127.0.0.1:4300"
echo "  Root app + generated-apps re-applied; refresh Argo UI if still empty."
