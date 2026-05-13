#!/usr/bin/env bash
# Sets a known Argo CD admin password (updates argocd-secret + initial-admin-secret) and restarts the API server.
# Requires: kubectl. For bcrypt: htpasswd (apache2-utils / httpd) OR docker.
set -euo pipefail

NEW_PASS="${ARGOCD_NEW_ADMIN_PASSWORD:-$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)}"

bcrypt_for_password() {
  local pass="$1"
  if command -v htpasswd >/dev/null 2>&1; then
    htpasswd -nbBC 10 admin "$pass" | cut -d: -f2
    return 0
  fi
  if command -v docker >/dev/null 2>&1; then
    docker run --rm httpd:2.4-alpine htpasswd -nbBC 10 admin "$pass" | cut -d: -f2
    return 0
  fi
  echo "Error: install htpasswd (e.g. brew install httpd) or Docker to generate bcrypt hashes." >&2
  exit 1
}

if ! kubectl get ns argocd >/dev/null 2>&1; then
  echo "Error: namespace argocd not found." >&2
  exit 1
fi

HASH="$(bcrypt_for_password "$NEW_PASS")"
MTIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

PATCH="$(H="$HASH" M="$MTIME" python3 -c 'import json,os; print(json.dumps({"stringData":{"admin.password":os.environ["H"],"admin.passwordMtime":os.environ["M"]}}))')"
kubectl -n argocd patch secret argocd-secret --type merge -p "$PATCH"

kubectl -n argocd create secret generic argocd-initial-admin-secret \
  --from-literal=password="$NEW_PASS" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n argocd rollout restart deployment/argocd-server
kubectl -n argocd rollout status deployment/argocd-server --timeout=120s

echo
echo "Argo CD admin password has been set."
echo "Username: admin"
echo "Password: $NEW_PASS"
echo "(To set your own: ARGOCD_NEW_ADMIN_PASSWORD='your-secret' $0)"
