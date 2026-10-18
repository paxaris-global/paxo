# Move Paxo + Cursor knowledge to a new account / machine

Chat history does **not** fully transfer between Cursor accounts. Put durable knowledge in **git + skills + rules**, then sign into the new account on the new machine.

## Timeline

| Phase | Dates | Action |
|-------|--------|--------|
| **Active on this system** | through **23 Oct 2026** | Keep working here; commit hybrid fixes; keep skill/docs in sync |
| **Cutover** | **24 Oct 2026** (or when you switch machines) | Push all repos → run export zip → import on new account |

Until cutover, do **not** abandon this machine’s stack. Refresh the transfer pack after meaningful skill/doc changes:

```bash
bash paxo/scripts/export-cursor-paxo-pack.sh
# → ~/Desktop/cursor-paxo-transfer-YYYYMMDD.zip
```

## Fastest path (cutover day)

1. **Push** `paxo`, `paxo_frontend`, `product-management-service` (and any other repos you touched).
2. Run `bash paxo/scripts/export-cursor-paxo-pack.sh` one last time.
3. On the new machine: clone the same workspace layout, install Colima/Minikube/Node/Java.
4. Copy Cursor personal skills **or** use the project skill from git:
   - In repo: `paxo/.cursor/skills/paxo-hybrid-local/`
   - Personal: `~/.cursor/skills/paxo-hybrid-local/`
5. Paste **User Rules** into Cursor Settings → Rules (`USER_RULES.md` inside the zip).
6. Open workspace → first prompt (below).

## What transfers vs what does not

| Item | Transfers via |
|------|----------------|
| Code + hybrid scripts | Git push / pull |
| Agent skill (hybrid ops) | Git `.cursor/skills/` or zip → `~/.cursor/skills/` |
| Workspace rule (concise replies) | Git / workspace `.cursor/rules/` |
| Your User Rules (commit/PR style, etc.) | Manual paste or zip `USER_RULES.md` |
| This chat / agent memories | **No** — skill + this doc replace them |
| Docker volumes / MySQL data | Not in git — recreate or dump DB if needed |
| Minikube cluster state | Recreate; re-apply `product-apps` + provision products |
| Secrets / tokens | Re-login (`gh auth`, Docker Hub, kubeconfig) |

## Repos that contain this work

Commit and push (at minimum):

- `paxo` — `local-hybrid/`, `k8/product-apps.yaml`, hybrid scripts, skill, this doc
- `paxo_frontend` — `proxy.conf.js`, showcase URL util, home/keycloak status tweaks
- `product-management-service` — catalog list/sync + provisioning image sed fix

Skip committing: `.angular/cache`, `target/`, `.idea/`.

## User Rules to paste (new Cursor account)

Copy from Cursor → Settings → Rules on the old account, or use the exported `USER_RULES.md`. At minimum keep:

- Clear/concise responses
- Git commit protocol (only when asked; HEREDOC messages; no force push)
- PR creation via `gh`
- Skills: read `paxo-hybrid-local` when working on Paxo hybrid

## First prompt on the new account

```text
Workspace is paxaris-repos. Read paxo/.cursor/skills/paxo-hybrid-local/SKILL.md
and paxo/CURSOR_ACCOUNT_TRANSFER.md. I cut over after 23 Oct 2026.
Start the hybrid stack and verify gateway :8085, PMS :8088, ng :4300,
and Open Product via NodePort.
```

## Architecture reminder

- **Compose** = Paxo core (identity, PMS, gateway, KC, MySQL)
- **Argo** = products only (`product-apps` + FE/BE apps)
- Missing PMS/identity in Argo UI is **expected**
