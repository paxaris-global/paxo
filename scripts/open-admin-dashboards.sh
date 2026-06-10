#!/usr/bin/env bash
# Start Keycloak + Argo CD port-forwards and open in the system browser (Chrome/Safari).
# Use this instead of clicking links in Cursor — embedded preview cannot load these UIs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/local-ports.sh
source "$ROOT_DIR/scripts/local-ports.sh"

KEYCLOAK_URL="http://localhost:${PAXO_KEYCLOAK_NODE_PORT}/admin/"
ARGOCD_URL="http://127.0.0.1:${PAXO_ARGOCD_LOCAL_PORT}/"

"$ROOT_DIR/scripts/start-admin-dashboards.sh"

echo
echo "Opening in your default browser (not Cursor preview)…"

if command -v open >/dev/null 2>&1; then
  open "$KEYCLOAK_URL"
  sleep 1
  open "$ARGOCD_URL"
else
  echo "Run manually in Chrome/Safari:"
  echo "  $KEYCLOAK_URL"
  echo "  $ARGOCD_URL"
fi

echo
echo "Keycloak login: admin / admin@123"
echo -n "Argo CD login:  admin / "
"$ROOT_DIR/scripts/print-argocd-admin-password.sh" 2>/dev/null | tail -1 || echo "(run ./scripts/print-argocd-admin-password.sh)"
