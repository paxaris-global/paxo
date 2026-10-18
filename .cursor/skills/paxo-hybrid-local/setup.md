# Hybrid local setup

## Timeline

| When | Where | What |
|------|--------|------|
| **Through 23 Oct 2026** | This Mac | Daily hybrid work; keep committing; re-run export zip if skills/docs change |
| **24 Oct 2026 onward** | New Cursor account / machine | Pull git, import zip/skills, follow `CURSOR_ACCOUNT_TRANSFER.md` |

## Prerequisites

- macOS with ~16GB+ RAM
- Docker via **Colima** (or Docker Desktop); set `DOCKER_HOST=unix://${HOME}/.colima/default/docker.sock`
- Minikube, kubectl, Argo CD in cluster
- Node 22+, Java 21, Maven (for rebuilding jars)
- Cloned repos under one workspace folder (e.g. `paxaris-repos/`):
  - `paxo`, `paxo_frontend`, `product-management-service`, `identity_service`, `api-gateway`

## One-time

1. Start Colima + Minikube with enough CPU/RAM for **1–2 products** only.
2. Install Argo CD; apply secrets used by product apps.
3. Build/push or pull `paxarisdocker` images as needed.
4. Build jars for Compose mounts:
   - `api-gateway/target/*.jar`
   - `identity_service/target/*.jar`
   - `product-management-service/target/*.jar`
5. Apply `paxo/k8/product-apps.yaml` (watches `k8/generated-apps`).
6. Copy Cursor skill: `.cursor/skills/paxo-hybrid-local/` (already in repo) and/or `~/.cursor/skills/paxo-hybrid-local/`.

## Daily

```bash
export DOCKER_HOST=unix://${HOME}/.colima/default/docker.sock
bash paxo/scripts/start-hybrid-stack.sh
# open http://localhost:4300
```

## Local-only passwords (dev)

Compose uses trivial local passwords (`root` / `admin@123`). Do not reuse in shared/prod.

## Capacity

On 16GB hybrid: safely **1–2** product apps in Minikube. Do not deploy full core into Argo.
