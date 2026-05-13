#!/usr/bin/env bash
set -euo pipefail

if ! kubectl get ns argocd >/dev/null 2>&1; then
  echo "Error: namespace 'argocd' not found." >&2
  exit 1
fi

if ! kubectl -n argocd get secret argocd-initial-admin-secret >/dev/null 2>&1; then
  echo "Error: secret argocd-initial-admin-secret not found." >&2
  echo "If the admin password was already rotated, use: argocd account update-password" >&2
  exit 1
fi

RAW="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
if [[ "$RAW" == \$2* ]]; then
  echo "Warning: secret holds a bcrypt hash, not a plaintext password (common after 'argocd admin initial-password reset')." >&2
  echo "Run: ./scripts/set-argocd-admin-password.sh" >&2
  exit 1
fi
printf '%s\n' "$RAW"
