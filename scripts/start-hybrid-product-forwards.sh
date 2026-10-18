#!/usr/bin/env bash
# Hybrid local: port-forward each product *-frontend / *-backend NodePort to localhost
# so ng serve /product-ui/... proxy and "Open product" links work without paxo-frontend nginx.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.local-runtime"
NS="${KUBECTL_NAMESPACE:-default}"
mkdir -p "$RUNTIME_DIR"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Error: '$1' required" >&2; exit 1; }
}

require_cmd kubectl
require_cmd nc

start_resilient_forward() {
  local name="$1" service="$2" local_port="$3" remote_port="$4"
  local log_file="$RUNTIME_DIR/$name.log"
  local pid_file="$RUNTIME_DIR/$name.pid"

  if [[ -f "$pid_file" ]]; then
    local old
    old="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "${old:-}" ]] && kill -0 "$old" >/dev/null 2>&1; then
      echo "  already running: $name (pid $old) → :$local_port"
      return 0
    fi
    rm -f "$pid_file"
  fi

  pkill -f "kubectl.*port-forward.*svc/$service.*${local_port}:${remote_port}" >/dev/null 2>&1 || true

  nohup bash -c '
    set -u
    child=""
    cleanup() {
      [[ -n "${child:-}" ]] && kill "$child" >/dev/null 2>&1 || true
      exit 0
    }
    trap "" HUP
    trap cleanup TERM INT
    while true; do
      kubectl -n "$4" port-forward "svc/$1" "$2:$3" --address 127.0.0.1 &
      child=$!
      wait "$child" || true
      child=""
      sleep 2
    done
  ' _ "$service" "$local_port" "$remote_port" "$NS" >"$log_file" 2>&1 &
  echo $! >"$pid_file"
  disown -h "$(cat "$pid_file")" 2>/dev/null || true

  for ((i = 1; i <= 30; i++)); do
    if nc -z 127.0.0.1 "$local_port" >/dev/null 2>&1; then
      echo "  ok: svc/$service → http://127.0.0.1:${local_port}"
      return 0
    fi
    sleep 0.5
  done
  echo "  warn: timed out waiting for :$local_port (see $log_file)" >&2
}

echo "Hybrid product port-forwards (NodePort → localhost)"
while IFS=$'\t' read -r svc node_port; do
  [[ -z "${svc:-}" || -z "${node_port:-}" || "${node_port}" == "0" ]] && continue
  case "$svc" in
    *-frontend)
      start_resilient_forward "product-ui-${svc}" "$svc" "$node_port" 80
      ;;
    *-backend)
      # skip postgres/redis helpers
      if [[ "$svc" == *postgres* || "$svc" == *redis* ]]; then
        continue
      fi
      start_resilient_forward "product-api-${svc}" "$svc" "$node_port" 8080
      ;;
  esac
done < <(
  kubectl -n "$NS" get svc -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.ports[0].nodePort}{"\n"}{end}' 2>/dev/null \
    | awk -F'\t' 'NF==2 && $2!="" && $2!="<no value>"'
)

echo
echo "Open product via Paxo UI: http://localhost:4300/product-ui/{realm}/{product}/"
echo "(requires ng serve proxy + these forwards)"
echo "Stop: pkill -f 'product-ui-|product-api-' ; rm -f $RUNTIME_DIR/product-ui-*.pid $RUNTIME_DIR/product-api-*.pid"
