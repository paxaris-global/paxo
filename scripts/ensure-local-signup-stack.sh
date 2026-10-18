#!/usr/bin/env bash
# Bring up durable Create Realm backends via Docker Compose (restart: unless-stopped).
# Usage:
#   ./scripts/ensure-local-signup-stack.sh            # up -d + wait
#   ./scripts/ensure-local-signup-stack.sh --probe    # also POST test signup
#   ./scripts/ensure-local-signup-stack.sh --status
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.local-runtime"
COMPOSE_FILE="$ROOT_DIR/local-hybrid/docker-compose.signup.yml"
LOCK_DIR="$RUNTIME_DIR/ensure-signup.lockdir"
PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
export PATH
export DOCKER_HOST="${DOCKER_HOST:-unix:///Users/rohitm/.colima/default/docker.sock}"
mkdir -p "$RUNTIME_DIR"

MODE="${1:-up}"
log() { echo "[ensure-signup $(date '+%H:%M:%S')] $*" | tee -a "$RUNTIME_DIR/ensure-signup.log"; }
http_code() { curl -m "${2:-3}" -sS -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || echo 000; }
dc() { docker compose -f "$COMPOSE_FILE" "$@"; }

status() {
  log "kc=$(http_code http://127.0.0.1:8080/) id=$(http_code http://127.0.0.1:8087/actuator/health) gw=$(http_code http://127.0.0.1:8085/actuator/health) ui=$(http_code http://127.0.0.1:4300/)"
  dc ps
}

if [[ "$MODE" == "--status" ]]; then status; exit 0; fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  holder=$(cat "$LOCK_DIR/pid" 2>/dev/null || echo "")
  if [[ -n "$holder" ]] && kill -0 "$holder" 2>/dev/null; then
    log "another ensure run (pid=$holder) is active; exiting"
    exit 0
  fi
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" || { log "ERROR: cannot acquire $LOCK_DIR"; exit 1; }
fi
echo $$ >"$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT

docker info >/dev/null 2>&1 || {
  log "starting docker in colima"
  limactl shell colima -- sudo service docker start >/dev/null 2>&1 || colima start >/dev/null 2>&1 || true
  sleep 3
}
docker info >/dev/null 2>&1 || { log "ERROR: docker/colima down"; exit 1; }

# Free host ports if leftover kubectl/java hold them
for p in 8080 8085 8087 3307; do
  for pid in $(lsof -nP -iTCP:$p -sTCP:LISTEN -t 2>/dev/null); do
    cmd=$(ps -o comm= -p "$pid" 2>/dev/null || true)
    case "$cmd" in *kubectl*|*java*) kill "$pid" 2>/dev/null || true ;; esac
  done
done
docker rm -f keycloak-local paxo-mysql-signup 2>/dev/null || true

dc up -d --remove-orphans >>"$RUNTIME_DIR/ensure-signup.log" 2>&1 || { log "ERROR: compose up failed"; tail -20 "$RUNTIME_DIR/ensure-signup.log"; exit 1; }

for _ in $(seq 1 120); do
  if [[ "$(http_code http://127.0.0.1:8085/actuator/health)" == "200" && "$(http_code http://127.0.0.1:8087/actuator/health)" == "200" ]]; then
    break
  fi
  sleep 3
done
status

if [[ "$MODE" == "--probe" ]]; then
  realm="probe$(date +%m%d%H%M%S)"
  base=http://127.0.0.1:4300
  [[ "$(http_code $base/)" == "000" ]] && base=http://127.0.0.1:8085
  code=$(curl -m 180 -sS -o "$RUNTIME_DIR/signup-probe.json" -w '%{http_code}' -X POST "$base/identity/signup" \
    -H 'Content-Type: application/json' -d "{\"realmName\":\"$realm\",\"adminPassword\":\"Admin@12345\"}")
  log "signup probe via $base realm=$realm HTTP=$code"
  cat "$RUNTIME_DIR/signup-probe.json" 2>/dev/null | head -c 500; echo
  [[ "$code" == "200" || "$code" == "201" ]]
fi
