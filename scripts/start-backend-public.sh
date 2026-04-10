#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.ngrok-runtime"
NGROK_SYSTEM_CONFIG="${HOME}/Library/Application Support/ngrok/ngrok.yml"
NGROK_PROJECT_CONFIG="$ROOT_DIR/ngrok/ngrok.yml"

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

require_cmd kubectl
require_cmd ngrok
require_cmd nc
require_cmd curl
require_cmd python3

ENV_FILE="$ROOT_DIR/.env"

# Auto-sync GitHub provisioning env into product-management-service from local .env.
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_ORG:-}" ]]; then
    PAXO_ORG_VALUE="${PAXO_ORG:-paxaris-global}"
    PAXO_REPO_VALUE="${PAXO_REPO:-paxo}"

    if kubectl get ns argocd >/dev/null 2>&1; then
      kubectl -n argocd create secret generic github-repo-creds-generated \
        --from-literal=url="https://github.com/${GITHUB_ORG}" \
        --from-literal=username="git" \
        --from-literal=password="${GITHUB_TOKEN}" \
        --dry-run=client -o yaml | kubectl apply -f - >/dev/null
      kubectl -n argocd label secret github-repo-creds-generated argocd.argoproj.io/secret-type=repo-creds --overwrite >/dev/null

      kubectl -n argocd create secret generic github-repo-paxo \
        --from-literal=type="git" \
        --from-literal=url="https://github.com/${PAXO_ORG_VALUE}/${PAXO_REPO_VALUE}.git" \
        --from-literal=username="git" \
        --from-literal=password="${GITHUB_TOKEN}" \
        --dry-run=client -o yaml | kubectl apply -f - >/dev/null
      kubectl -n argocd label secret github-repo-paxo argocd.argoproj.io/secret-type=repository --overwrite >/dev/null
    fi

    kubectl set env deployment/product-management-service \
      GITHUB_TOKEN="$GITHUB_TOKEN" \
      GITHUB_ORG="$GITHUB_ORG" \
      PAXO_ORG="$PAXO_ORG_VALUE" \
      PAXO_REPO="$PAXO_REPO_VALUE" \
      DOCKER_USERNAME="${DOCKER_USERNAME:-}" \
      DOCKER_PASSWORD="${DOCKER_PASSWORD:-}" \
      >/dev/null
    kubectl rollout status deployment/product-management-service --timeout=180s >/dev/null
  else
    echo "Warning: GITHUB_TOKEN or GITHUB_ORG missing in $ENV_FILE."
    echo "         Product provisioning to GitHub may fail until these are set."
  fi
else
  echo "Warning: $ENV_FILE not found; skipping GitHub env auto-config."
fi

for svc in paxo-frontend keycloak api-gateway identity-service product-management-service jaeger; do
  if ! kubectl get svc "$svc" >/dev/null 2>&1; then
    echo "Error: Kubernetes service '$svc' not found." >&2
    exit 1
  fi
done

echo "Starting full stack public access (frontend + backend microservices)..."
echo "Syncing provisioning environment from .env (GitHub/Argo prerequisites)..."
echo

# Clean stale processes for a consistent start.
pkill -f "kubectl port-forward svc/paxo-frontend" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/keycloak" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/api-gateway" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/identity-service" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/product-management-service" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/jaeger" >/dev/null 2>&1 || true
pkill -f "ngrok" >/dev/null 2>&1 || true

nohup kubectl port-forward svc/paxo-frontend 4200:80 >"$RUNTIME_DIR/frontend.log" 2>&1 &
echo $! >"$RUNTIME_DIR/frontend.pid"

nohup kubectl port-forward svc/keycloak 8080:8080 >"$RUNTIME_DIR/keycloak.log" 2>&1 &
echo $! >"$RUNTIME_DIR/keycloak.pid"

nohup kubectl port-forward svc/api-gateway 8085:8085 >"$RUNTIME_DIR/backend-gateway.log" 2>&1 &
echo $! >"$RUNTIME_DIR/backend-gateway.pid"

nohup kubectl port-forward svc/identity-service 8087:8087 >"$RUNTIME_DIR/backend-identity.log" 2>&1 &
echo $! >"$RUNTIME_DIR/backend-identity.pid"

nohup kubectl port-forward svc/product-management-service 8088:8088 >"$RUNTIME_DIR/backend-product.log" 2>&1 &
echo $! >"$RUNTIME_DIR/backend-product.pid"

nohup kubectl port-forward svc/jaeger 16686:16686 >"$RUNTIME_DIR/jaeger.log" 2>&1 &
echo $! >"$RUNTIME_DIR/jaeger.pid"

if ! wait_for_port 4200 || ! wait_for_port 8080 || ! wait_for_port 8085 || ! wait_for_port 8087 || ! wait_for_port 8088 || ! wait_for_port 16686; then
  echo "Error: backend services did not open local ports in time." >&2
  exit 1
fi

if [[ -f "$NGROK_PROJECT_CONFIG" ]]; then
  nohup ngrok http 4200 --config "$NGROK_SYSTEM_CONFIG" --config "$NGROK_PROJECT_CONFIG" >"$RUNTIME_DIR/ngrok-backend.log" 2>&1 &
else
  nohup ngrok http 4200 --config "$NGROK_SYSTEM_CONFIG" >"$RUNTIME_DIR/ngrok-backend.log" 2>&1 &
fi
echo $! >"$RUNTIME_DIR/ngrok-backend.pid"

if ! wait_for_port 4040; then
  echo "Error: ngrok did not start." >&2
  tail -n 40 "$RUNTIME_DIR/ngrok-backend.log" >&2 || true
  exit 1
fi

PUBLIC_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | python3 -c 'import sys, json; d=json.load(sys.stdin); ts=d.get("tunnels", []); print(ts[0]["public_url"] if ts else "")')

if [[ -z "$PUBLIC_URL" ]]; then
  echo "Error: Could not read ngrok public URL." >&2
  tail -n 40 "$RUNTIME_DIR/ngrok-backend.log" >&2 || true
  exit 1
fi

echo "=========================================="
echo "FULL STACK PUBLIC ACCESS READY"
echo "=========================================="
echo
echo "Public Base URL:        $PUBLIC_URL"
echo
echo "Frontend:               $PUBLIC_URL"
echo "Gateway Health:         $PUBLIC_URL/gateway/actuator/health"
echo "Identity Signup (POST): $PUBLIC_URL/identity/signup"
echo "Identity Login:         $PUBLIC_URL/identity/{realm}/login"
echo "Product Health:         $PUBLIC_URL/project/provision/health"
echo
echo "Direct Local (your Mac):"
echo "Frontend:               http://127.0.0.1:4200"
echo "Keycloak:               http://127.0.0.1:8080"
echo "API Gateway:            http://127.0.0.1:8085"
echo "Identity Service:       http://127.0.0.1:8087"
echo "Product Service:        http://127.0.0.1:8088"
echo "Jaeger UI:              http://127.0.0.1:16686"
echo
echo "Stop backend public access:"
echo "  ./scripts/stop-backend-public.sh"
echo
echo "=========================================="
