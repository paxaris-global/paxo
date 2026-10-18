#!/usr/bin/env bash
set -euo pipefail
STAMP="$(date +%Y%m%d)"
OUT="${1:-$HOME/Desktop/cursor-paxo-transfer-$STAMP.zip}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/skills" "$TMP/workspace-cursor"

# Personal skill
if [[ -d "$HOME/.cursor/skills/paxo-hybrid-local" ]]; then
  cp -R "$HOME/.cursor/skills/paxo-hybrid-local" "$TMP/skills/"
fi
# Workspace skill (parent of paxo)
WS_SKILL="$(cd "$(dirname "$0")/../.." && pwd)/.cursor/skills/paxo-hybrid-local"
if [[ -d "$WS_SKILL" ]]; then
  cp -R "$WS_SKILL" "$TMP/skills/paxo-hybrid-local-workspace"
fi
# From this repo
REPO_SKILL="$(cd "$(dirname "$0")/.." && pwd)/.cursor/skills/paxo-hybrid-local"
if [[ -d "$REPO_SKILL" ]]; then
  cp -R "$REPO_SKILL" "$TMP/skills/paxo-hybrid-local"
fi
cp "$(cd "$(dirname "$0")/.." && pwd)/CURSOR_ACCOUNT_TRANSFER.md" "$TMP/" 2>/dev/null || true
cp "$(cd "$(dirname "$0")/.." && pwd)/docs/paxo-hybrid-local/"* "$TMP/skills/paxo-hybrid-local/" 2>/dev/null || true

cat > "$TMP/USER_RULES.md" <<'RULES'
# Paste into Cursor Settings → Rules (new account)

## Clear and concise
- Simple language, short bullets, lead with the answer
- Skip filler; expand only when asked

## Git commits (only when I ask)
- Never update git config; never force-push main; never skip hooks unless asked
- Parallel: git status, git diff, git log — then stage and commit with HEREDOC message
- Do not commit secrets (.env, credentials)

## Pull requests (when I ask)
- Use gh; push -u if needed; HEREDOC body with Summary + Test plan

## Paxo hybrid
- When working on Paxo hybrid / Colima / Minikube / Open Product / Create Product:
  read and follow the paxo-hybrid-local skill
RULES

cat > "$TMP/README_IMPORT.md" <<'IMP'
# Import on new Cursor account / machine

1. Unzip this archive.
2. Copy `skills/paxo-hybrid-local` → `~/.cursor/skills/paxo-hybrid-local`
3. Open Cursor Settings → Rules and paste `USER_RULES.md`
4. `git pull` all paxaris repos (paxo, paxo_frontend, product-management-service)
5. Open workspace folder `paxaris-repos`
6. Optional: copy skills into `paxaris-repos/.cursor/skills/`
7. Run: `bash paxo/scripts/start-hybrid-stack.sh`
8. First chat: ask agent to follow paxo-hybrid-local skill
IMP

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
(
  cd "$TMP"
  zip -r "$OUT" . >/dev/null
)
echo "Wrote $OUT"
