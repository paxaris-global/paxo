#!/usr/bin/env bash
# Sync GitHub + Docker Hub credentials from paxo/.env into the kubernetes secret
# used by product-management-service (and related workloads).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${PAXO_ENV_FILE:-$ROOT_DIR/.env}"
NS="${KUBECTL_NAMESPACE:-default}"
SECRET_NAME="${GITHUB_CREDENTIALS_SECRET:-github-credentials}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' is not installed." >&2
    exit 1
  fi
}

load_env() {
  # Keep a valid token already exported in the shell (e.g. from --prompt).
  local pre_token="${GITHUB_TOKEN:-}"

  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: env file not found: $ENV_FILE" >&2
    echo "Copy .env.example to .env and set GITHUB_TOKEN (classic PAT with repo + org admin)." >&2
    exit 1
  fi
  # shellcheck disable=SC1090
  set -a
  source "$ENV_FILE"
  set +a

  if [[ -n "${pre_token// }" ]]; then
    GITHUB_TOKEN="$pre_token"
  fi
}

usage() {
  cat <<'EOF'
Sync GitHub + Docker Hub credentials into Kubernetes secret "github-credentials".

You do NOT need your GitHub account password or Mac Keychain for this script.

Option A — paste a new token interactively (recommended if .env token is expired):
  ./scripts/sync-github-credentials.sh --prompt
  (only asks for GITHUB_TOKEN starting with ghp_; not a password)

Option B — put a classic PAT in paxo/.env as GITHUB_TOKEN=ghp_... then:
  ./scripts/sync-github-credentials.sh

Create a token: https://github.com/settings/tokens/new
  - Type: classic
  - Scopes: repo, admin:org (for PaxarisGlobal), workflow
  - If org uses SSO: authorize the token for PaxarisGlobal after creating it
EOF
}

validate_github_token() {
  local token="$1"
  local org="$2"
  if [[ -z "${token// }" ]]; then
    echo "Error: GITHUB_TOKEN is empty in $ENV_FILE" >&2
    exit 1
  fi
  if [[ -z "${org// }" ]]; then
    echo "Error: GITHUB_ORG is empty in $ENV_FILE" >&2
    exit 1
  fi

  local user_code org_code
  user_code="$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/user")"
  if [[ "$user_code" != "200" ]]; then
    echo "Error: GITHUB_TOKEN is invalid or expired (GET /user returned HTTP ${user_code})." >&2
    echo "Create a new classic PAT at https://github.com/settings/tokens with repo + admin:org (PaxarisGlobal)." >&2
    exit 1
  fi

  org_code="$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/orgs/${org}")"
  if [[ "$org_code" != "200" ]]; then
    echo "Error: token cannot access org '${org}' (HTTP ${org_code}). Check GITHUB_ORG and org membership." >&2
    exit 1
  fi

  echo "GitHub token OK for user and org ${org}."
}

apply_secret() {
  kubectl -n "$NS" create secret generic "$SECRET_NAME" \
    --from-literal=GITHUB_TOKEN="$GITHUB_TOKEN" \
    --from-literal=GITHUB_ORG="$GITHUB_ORG" \
    --from-literal=DOCKER_USERNAME="${DOCKER_USERNAME:-}" \
    --from-literal=DOCKER_PASSWORD="${DOCKER_PASSWORD:-}" \
    --dry-run=client -o yaml | kubectl -n "$NS" apply -f -
}

restart_product_management() {
  if kubectl -n "$NS" get deployment product-management-service >/dev/null 2>&1; then
    kubectl -n "$NS" rollout restart deployment/product-management-service
    kubectl -n "$NS" rollout status deployment/product-management-service --timeout=120s
  else
    echo "Note: deployment/product-management-service not found in namespace ${NS}; secret updated only."
  fi
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  require_cmd kubectl
  require_cmd curl
  load_env

  if [[ "${1:-}" == "--prompt" ]]; then
    echo "Paste a GitHub classic PAT (ghp_...). This is NOT your GitHub login password."
    read -rsp "GITHUB_TOKEN: " GITHUB_TOKEN
    echo
    read -rp "GITHUB_ORG [${GITHUB_ORG:-PaxarisGlobal}]: " org_input
    GITHUB_ORG="${org_input:-${GITHUB_ORG:-PaxarisGlobal}}"
    echo ""
    echo "Tip: save the same token in paxo/.env as GITHUB_TOKEN=... for next time."
  fi

  validate_github_token "$GITHUB_TOKEN" "$GITHUB_ORG"
  apply_secret
  restart_product_management
  echo "Done. Retry Create Product in Paxo UI."
}

main "$@"
