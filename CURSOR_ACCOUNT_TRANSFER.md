# Move Paxo + Cursor knowledge to a new account / machine

Chat history does **not** fully transfer between Cursor accounts. Put durable knowledge in **git + skills + rules**, then sign into the new account on the new machine.

## Fastest path (recommended)

1. **Push these commits** to GitHub (all repos you changed).
2. On the new machine: clone the same workspace layout, install Colima/Minikube/Node/Java.
3. Copy Cursor personal skills (below) **or** rely on the project skill already in git:
   - Project (follows the repo): `paxaris-repos/.cursor/skills/paxo-hybrid-local/`
   - Personal (all projects): `~/.cursor/skills/paxo-hybrid-local/`
4. Paste **User Rules** into Cursor Settings → Rules on the new account (see section below).
5. Open the workspace → ask: `Follow paxo-hybrid-local skill and start the hybrid stack`.

Optional zip of personal Cursor bits (run on old machine):

```bash
bash paxo/scripts/export-cursor-paxo-pack.sh
# → ~/Desktop/cursor-paxo-transfer-YYYYMMDD.zip
```

On the new machine: unzip into `~/.cursor/` (merge `skills/`) and paste rules from `USER_RULES.md` inside the zip.

## What transfers vs what does not

| Item | Transfers via |
|------|----------------|
| Code + hybrid scripts | Git push / pull |
| Agent skill (hybrid ops) | Git `.cursor/skills/` or zip → `~/.cursor/skills/` |
| Workspace rule (concise replies) | Git `.cursor/rules/` |
| Your User Rules (commit/PR style, etc.) | Manual paste or zip `USER_RULES.md` |
| This chat / agent memories | **No** — skill + this doc replace them |
| Docker volumes / MySQL data | Not in git — recreate or dump DB if needed |
| Minikube cluster state | Recreate; re-apply `product-apps` + provision products |
| Secrets / tokens | Re-login (`gh auth`, Docker Hub, kubeconfig) |

## Repos that contain this work

Commit and push (at minimum):

- `paxo` — `local-hybrid/`, `k8/product-apps.yaml`, hybrid scripts, cleaned generated leftovers
- `paxo_frontend` — `proxy.conf.js`, showcase URL util, home/keycloak status tweaks
- `product-management-service` — catalog list/sync + provisioning image sed fix

Skip committing: `.angular/cache`, `target/`, `.idea/`.

## User Rules to paste (new Cursor account)

Copy from Cursor → Settings → Rules on the old account, or use the exported `USER_RULES.md`. At minimum keep:

- Clear/concise responses
- Git commit protocol (only when asked; HEREDOC messages; no force push)
- PR creation via `gh`
- Frontend design constraints (if you still want them)
- Skills: read `paxo-hybrid-local` when working on Paxo hybrid

## First prompt on the new account

```text
Workspace is paxaris-repos. Read .cursor/skills/paxo-hybrid-local/SKILL.md
and CURSOR_ACCOUNT_TRANSFER.md. Start the hybrid stack and verify
gateway :8085, PMS :8088, ng :4300, and Open Product via NodePort.
```

## Architecture reminder

- **Compose** = Paxo core (identity, PMS, gateway, KC, MySQL)
- **Argo** = products only (`product-apps` + FE/BE apps)
- Missing PMS/identity in Argo UI is **expected**
