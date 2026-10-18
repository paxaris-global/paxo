#!/usr/bin/env bash
# Switch Create Realm to self-contained Docker Compose (no Minikube backends).
set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
export DOCKER_HOST="${DOCKER_HOST:-unix:///Users/rohitm/.colima/default/docker.sock}"

echo "== stopping old watchers / port-forwards"
pkill -f 'pf-signup-ports.sh' 2>/dev/null || true
pkill -f 'ensure-local-signup-stack.sh --watch' 2>/dev/null || true
pkill -f 'port-forward svc/' 2>/dev/null || true
rm -rf "$ROOT_DIR/.local-runtime/ensure-signup.lockdir"

echo "== releasing host ports"
for p in 8080 8085 8087 3307; do
  for pid in $(lsof -nP -iTCP:$p -sTCP:LISTEN -t 2>/dev/null); do
    echo "  kill $pid on :$p"
    kill "$pid" 2>/dev/null || true
  done
done
docker rm -f keycloak-local paxo-mysql-signup 2>/dev/null || true

# Best-effort: free Minikube RAM if cluster is up
kubectl scale deploy/keycloak deploy/identity-service deploy/api-gateway --replicas=0 2>/dev/null || true

sleep 2
exec "$ROOT_DIR/scripts/ensure-local-signup-stack.sh" --probe
