#!/usr/bin/env bash
# Start hybrid local: Compose core + product NodePort forwards + ng serve :4300
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="$(cd "$ROOT_DIR/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/local-hybrid/docker-compose.signup.yml"
FRONTEND_DIR="$WORKSPACE_DIR/paxo_frontend"
NG_LOG="${PAXO_NG_LOG:-/tmp/ng-4300.log}"
NG_PID_FILE="${PAXO_NG_PID_FILE:-/tmp/ng-4300.pid}"

export DOCKER_HOST="${DOCKER_HOST:-unix://${HOME}/.colima/default/docker.sock}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Error: '$1' required" >&2; exit 1; }
}

require_cmd docker
require_cmd kubectl
require_cmd npx

echo "==> Compose core (identity / PMS / gateway / Keycloak / MySQL)"
docker compose -f "$COMPOSE_FILE" up -d

echo "==> Ensure Argo product-apps Application exists"
kubectl apply -f "$ROOT_DIR/k8/product-apps.yaml" >/dev/null

echo "==> Product NodePort forwards"
bash "$ROOT_DIR/scripts/start-hybrid-product-forwards.sh"

if [[ ! -d "$FRONTEND_DIR" ]]; then
  echo "Warn: paxo_frontend not found at $FRONTEND_DIR — skip ng serve" >&2
  exit 0
fi

if lsof -iTCP:4300 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "==> ng serve already listening on :4300"
else
  echo "==> Starting ng serve on :4300"
  (
    cd "$FRONTEND_DIR"
    nohup npx ng serve --port 4300 --host 0.0.0.0 --proxy-config proxy.conf.js \
      >"$NG_LOG" 2>&1 &
    echo $! >"$NG_PID_FILE"
  )
  for i in $(seq 1 60); do
    if curl -sf -m 2 -o /dev/null http://127.0.0.1:4300/; then
      echo "  ng ready"
      break
    fi
    sleep 2
  done
fi

echo
echo "Paxo UI:     http://localhost:4300"
echo "Gateway:     http://127.0.0.1:8085"
echo "PMS:         http://127.0.0.1:8088"
echo "Keycloak:    http://127.0.0.1:8080"
echo "Open Product uses NodePort (e.g. http://127.0.0.1:32100/) — see start-hybrid-product-forwards.sh"
echo "ng log:      $NG_LOG"
