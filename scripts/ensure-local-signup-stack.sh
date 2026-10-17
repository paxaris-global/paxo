#!/usr/bin/env bash
# Keep Create Realm backends alive (identity + gateway + Keycloak + MySQL PF).
# Usage:
#   ./scripts/ensure-local-signup-stack.sh           # one-shot ensure
#   ./scripts/ensure-local-signup-stack.sh --watch   # restart whenever something dies
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_DIR="$(cd "$ROOT_DIR/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.local-runtime"
mkdir -p "$RUNTIME_DIR"

WATCH=0
[[ "${1:-}" == "--watch" ]] && WATCH=1

log() { echo "[ensure-signup $(date '+%H:%M:%S')] $*"; }

port_up() {
  nc -z 127.0.0.1 "$1" >/dev/null 2>&1
}

http_ok() {
  local url="$1" expect="${2:-200}"
  local code
  code=$(curl -m 2 -sS -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo 000)
  if [[ "$expect" == "302" ]]; then
    [[ "$code" == "302" || "$code" == "200" ]]
  else
    [[ "$code" == "$expect" ]]
  fi
}

start_java_heap() {
  local name="$1" jar="$2" xms="$3" xmx="$4"
  shift 4
  local pid_file="$RUNTIME_DIR/${name}-local.pid"
  local log_file="$RUNTIME_DIR/${name}-local.log"
  if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" >/dev/null 2>&1; then
    return 0
  fi
  [[ -f "$jar" ]] || { log "ERROR: missing jar $jar"; return 1; }
  rm -f "$pid_file"
  nohup env OTEL_SDK_DISABLED=true "$@" java "$xms" "$xmx" -jar "$jar" \
    >"$log_file" 2>&1 < /dev/null &
  echo $! >"$pid_file"
  disown $! 2>/dev/null || true
  log "started $name pid=$(cat "$pid_file")"
}

ensure_mysql_pf() {
  if port_up 3307; then return 0; fi
  pkill -f 'port-forward svc/mysql 3307:3306' 2>/dev/null || true
  kubectl scale deploy/mysql --replicas=1 >/dev/null 2>&1 || true
  nohup kubectl port-forward svc/mysql 3307:3306 --address 127.0.0.1 \
    >"$RUNTIME_DIR/pf-mysql.log" 2>&1 < /dev/null &
  echo $! >"$RUNTIME_DIR/pf-mysql.pid"
  disown $! 2>/dev/null || true
  local i
  for i in $(seq 1 30); do
    port_up 3307 && return 0
    sleep 1
  done
  log "ERROR: mysql port-forward :3307 failed"
  return 1
}

ensure_keycloak() {
  if http_ok http://127.0.0.1:8080/ 302; then return 0; fi
  # Host Docker Keycloak is stable; Minikube KC OOMs on ~6Gi nodes.
  kubectl scale deploy/keycloak --replicas=0 >/dev/null 2>&1 || true
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx keycloak-local; then
    docker start keycloak-local >/dev/null 2>&1 || true
  else
    docker run -d --name keycloak-local -p 8080:8080 \
      -e KEYCLOAK_ADMIN=admin \
      -e KEYCLOAK_ADMIN_PASSWORD='admin@123' \
      -e KC_DB=mysql \
      -e KC_DB_URL='jdbc:mysql://host.docker.internal:3307/keycloak_db' \
      -e KC_DB_USERNAME=root \
      -e KC_DB_PASSWORD=root \
      -e KC_DB_DRIVER=com.mysql.cj.jdbc.Driver \
      -e KC_HTTP_ENABLED=true \
      -e KC_HOSTNAME=localhost \
      -e KC_HOSTNAME_STRICT=false \
      -e JAVA_OPTS_KC_HEAP='-Xms512m -Xmx1024m' \
      quay.io/keycloak/keycloak:26.2.0 start-dev --http-relative-path=/ >/dev/null
  fi
  local i
  for i in $(seq 1 60); do
    http_ok http://127.0.0.1:8080/ 302 && return 0
    sleep 3
  done
  log "ERROR: Keycloak not ready on :8080"
  return 1
}

ensure_identity() {
  if http_ok http://127.0.0.1:8087/actuator/health 200; then return 0; fi
  pkill -f 'identity_service-0.0.1-SNAPSHOT.jar' 2>/dev/null || true
  sleep 1
  start_java_heap identity \
    "$REPOS_DIR/identity_service/target/identity_service-0.0.1-SNAPSHOT.jar" \
    -Xms256m -Xmx512m \
    SPRING_DATASOURCE_URL='jdbc:mysql://127.0.0.1:3307/identity_service?createDatabaseIfNotExist=true&allowPublicKeyRetrieval=true&useSSL=false' \
    SPRING_DATASOURCE_USERNAME=root \
    SPRING_DATASOURCE_PASSWORD=root \
    KEYCLOAK_BASE_URL=http://127.0.0.1:8080 \
    KEYCLOAK_REALM=master \
    KEYCLOAK_ADMIN=admin \
    KEYCLOAK_ADMIN_PASSWORD='admin@123' \
    PROJECT_MANAGER_URL=http://127.0.0.1:8088
  local i
  for i in $(seq 1 40); do
    http_ok http://127.0.0.1:8087/actuator/health 200 && return 0
    sleep 2
  done
  log "ERROR: identity not healthy (see $RUNTIME_DIR/identity-local.log)"
  return 1
}

ensure_gateway() {
  if http_ok http://127.0.0.1:8085/actuator/health 200; then return 0; fi
  pkill -f 'api-gateway-0.0.1-SNAPSHOT.jar' 2>/dev/null || true
  sleep 1
  start_java_heap gateway \
    "$REPOS_DIR/api-gateway/target/api-gateway-0.0.1-SNAPSHOT.jar" \
    -Xms128m -Xmx384m \
    KEYCLOAK_BASE_URL=http://127.0.0.1:8080 \
    IDENTITY_SERVICE_URL=http://127.0.0.1:8087 \
    PROJECT_MANAGEMENT_BASE_URL=http://127.0.0.1:8088
  local i
  for i in $(seq 1 40); do
    http_ok http://127.0.0.1:8085/actuator/health 200 && return 0
    sleep 2
  done
  log "ERROR: gateway not healthy (see $RUNTIME_DIR/gateway-local.log)"
  return 1
}

ensure_all() {
  ensure_mysql_pf
  ensure_keycloak
  ensure_identity
  ensure_gateway
  log "OK gw=:8085 id=:8087 kc=:8080 mysql=:3307"
}

ensure_all
if [[ "$WATCH" -eq 1 ]]; then
  log "watching every 15s (keeps Create Realm working)"
  while true; do
    sleep 15
    ensure_all || true
  done
fi
