#!/usr/bin/env bash
# Start Paxo core services locally (jars + ng serve) against Minikube MySQL/Keycloak/Jaeger.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOS_DIR="$(cd "$ROOT_DIR/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.local-runtime"
mkdir -p "$RUNTIME_DIR"

start_pf() {
  local name="$1"
  local resource="$2"
  local mapping="$3"
  local port="$4"
  local log="$RUNTIME_DIR/pf-${name}.log"
  if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
    echo "port-forward $name already up on :$port"
    return 0
  fi
  pkill -f "kubectl -n default port-forward ${resource} ${mapping}" 2>/dev/null || true
  nohup kubectl -n default port-forward "$resource" "$mapping" --address 127.0.0.1 >"$log" 2>&1 < /dev/null &
  echo $! >"$RUNTIME_DIR/pf-${name}.pid"
  disown $! 2>/dev/null || true
  local i
  for i in $(seq 1 30); do
    nc -z 127.0.0.1 "$port" >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "Error: port-forward $name failed on :$port (see $log)" >&2
  return 1
}

start_java() {
  local name="$1" jar="$2"
  shift 2
  local pid_file="$RUNTIME_DIR/${name}-local.pid"
  local log_file="$RUNTIME_DIR/${name}-local.log"
  if [[ ! -f "$jar" ]]; then
    echo "Error: jar not found for $name: $jar" >&2
    return 1
  fi
  if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" >/dev/null 2>&1; then
    echo "$name already running pid=$(cat "$pid_file")"
    return 0
  fi
  rm -f "$pid_file"
  nohup env "$@" java -jar "$jar" >"$log_file" 2>&1 < /dev/null &
  echo $! >"$pid_file"
  disown $! 2>/dev/null || true
  echo "started $name pid=$(cat "$pid_file") log=$log_file"
}

echo "==> Port-forwards (cluster infra)"
start_pf mysql svc/mysql 3307:3306 3307
start_pf keycloak svc/keycloak 8080:8080 8080
# Jaeger is optional locally (OTEL can be disabled); do not fail the whole stack if it is scaled down.
if ! start_pf jaeger-otlp svc/jaeger 4318:4318 4318; then
  echo "Warning: Jaeger OTLP port-forward unavailable; continuing with OTEL_SDK_DISABLED=true"
  export OTEL_SDK_DISABLED=true
fi

# Load secrets from paxo/.env when present (GITHUB_TOKEN, DOCKER_*, GITHUB_ORG)
if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
  echo "==> Loaded $ROOT_DIR/.env"
fi
GITHUB_TOKEN_VALUE="${GITHUB_TOKEN:-placeholder}"
GITHUB_ORG_VALUE="${GITHUB_ORG:-PaxarisGlobal}"
DOCKER_USERNAME_VALUE="${DOCKER_USERNAME:-placeholder}"
DOCKER_PASSWORD_VALUE="${DOCKER_PASSWORD:-placeholder}"

echo "==> Java services"
# Prefer underscore jar name from Maven; fall back to hyphenated artifact if present.
PRODUCT_JAR="$REPOS_DIR/product-management-service/target/product_management_service-0.0.1-SNAPSHOT.jar"
[[ -f "$PRODUCT_JAR" ]] || PRODUCT_JAR="$REPOS_DIR/product-management-service/target/product-management-service-0.0.1-SNAPSHOT.jar"

start_java product \
  "$PRODUCT_JAR" \
  SPRING_DATASOURCE_URL='jdbc:mysql://127.0.0.1:3307/centralized_data?createDatabaseIfNotExist=true&allowPublicKeyRetrieval=true&useSSL=false' \
  SPRING_DATASOURCE_USERNAME=root \
  SPRING_DATASOURCE_PASSWORD=root \
  GITHUB_TOKEN="$GITHUB_TOKEN_VALUE" \
  GITHUB_ORG="$GITHUB_ORG_VALUE" \
  DOCKER_USERNAME="$DOCKER_USERNAME_VALUE" \
  DOCKER_PASSWORD="$DOCKER_PASSWORD_VALUE" \
  SHOWCASE_PLAYWRIGHT_ENABLED=false \
  CATALOG_SYNC_KUBERNETES_ENABLED=false \
  OTEL_SDK_DISABLED="${OTEL_SDK_DISABLED:-false}" \
  OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318/v1/traces \
  PROVISIONING_BROWSER_HOST=127.0.0.1 \
  PROVISIONING_PAXO_PUBLIC_BASE_URL=http://127.0.0.1:4300

start_java identity \
  "$REPOS_DIR/identity_service/target/identity_service-0.0.1-SNAPSHOT.jar" \
  SPRING_DATASOURCE_URL='jdbc:mysql://127.0.0.1:3307/identity_service?createDatabaseIfNotExist=true&allowPublicKeyRetrieval=true&useSSL=false' \
  SPRING_DATASOURCE_USERNAME=root \
  SPRING_DATASOURCE_PASSWORD=root \
  KEYCLOAK_BASE_URL=http://127.0.0.1:8080 \
  KEYCLOAK_REALM=master \
  KEYCLOAK_ADMIN=admin \
  KEYCLOAK_ADMIN_PASSWORD='admin@123' \
  PROJECT_MANAGER_URL=http://127.0.0.1:8088 \
  IDENTITY_JWT_ISSUER_HOST_REWRITE_FROM=localhost \
  IDENTITY_JWT_ISSUER_HOST_REWRITE_TO=127.0.0.1 \
  OTEL_SDK_DISABLED="${OTEL_SDK_DISABLED:-false}" \
  OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318/v1/traces \
  DOCKER_USERNAME="$DOCKER_USERNAME_VALUE" \
  DOCKER_PASSWORD="$DOCKER_PASSWORD_VALUE" \
  GITHUB_ORG="$GITHUB_ORG_VALUE" \
  GITHUB_TOKEN="$GITHUB_TOKEN_VALUE"

start_java gateway \
  "$REPOS_DIR/api-gateway/target/api-gateway-0.0.1-SNAPSHOT.jar" \
  KEYCLOAK_BASE_URL=http://127.0.0.1:8080 \
  IDENTITY_SERVICE_URL=http://127.0.0.1:8087 \
  PROJECT_MANAGEMENT_BASE_URL=http://127.0.0.1:8088 \
  OTEL_SDK_DISABLED="${OTEL_SDK_DISABLED:-false}" \
  OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318/v1/traces

echo "==> Frontend (ng serve :4300)"
if [[ -f "$RUNTIME_DIR/frontend-local.pid" ]] && kill -0 "$(cat "$RUNTIME_DIR/frontend-local.pid")" >/dev/null 2>&1; then
  echo "frontend already running pid=$(cat "$RUNTIME_DIR/frontend-local.pid")"
else
  (
    cd "$REPOS_DIR/paxo_frontend"
    nohup npm start >"$RUNTIME_DIR/frontend-local.log" 2>&1 < /dev/null &
    echo $! >"$RUNTIME_DIR/frontend-local.pid"
    disown $! 2>/dev/null || true
  )
  echo "started frontend pid=$(cat "$RUNTIME_DIR/frontend-local.pid")"
fi

echo "==> Waiting for health"
for i in $(seq 1 60); do
  p=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8088/actuator/health || true)
  i_code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8087/actuator/health || true)
  g=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8085/actuator/health || true)
  f=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:4300/ || true)
  if [[ "$f" != "200" ]]; then
    f=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:4300/ || true)
  fi
  echo "try=$i product=$p identity=$i_code gateway=$g frontend=$f"
  if [[ "$p" == "200" && "$i_code" == "200" && "$g" == "200" && "$f" == "200" ]]; then
    break
  fi
  sleep 3
done

echo
echo "Paxo UI:     http://127.0.0.1:4300/"
echo "Gateway:     http://127.0.0.1:8085/actuator/health"
echo "Identity:    http://127.0.0.1:8087/actuator/health"
echo "Product API: http://127.0.0.1:8088/actuator/health"
echo "Keycloak:    http://127.0.0.1:8080/admin/ (admin / admin@123)"
echo "Logs:        $RUNTIME_DIR/*-local.log"
