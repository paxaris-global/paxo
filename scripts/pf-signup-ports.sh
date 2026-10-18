#!/usr/bin/env bash
set -u
PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"
RUNTIME="/Users/rohitm/paxaris-repos/paxo/.local-runtime"
mkdir -p "$RUNTIME"
log(){ echo "[pf-signup $(date '+%H:%M:%S')] $*" | tee -a "$RUNTIME/pf-signup.log"; }
pf(){
  local name="$1" svc="$2" localport="$3" remote="$4"
  while true; do
    if nc -z 127.0.0.1 "$localport" >/dev/null 2>&1; then
      sleep 5
      continue
    fi
    log "starting PF $name $localport->$svc:$remote"
    kubectl port-forward "svc/$svc" "${localport}:${remote}" --address 127.0.0.1 \
      >>"$RUNTIME/pf-${name}.log" 2>&1 || true
    log "PF $name exited; retry in 2s"
    sleep 2
  done
}
pf gateway api-gateway 8085 8085 &
pf identity identity-service 8087 8087 &
wait
