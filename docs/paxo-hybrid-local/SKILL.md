---
name: paxo-hybrid-local
description: >-
  Run and debug Paxo hybrid local: Docker Compose for core (identity, PMS,
  gateway, Keycloak, MySQL) plus Minikube/Argo for product apps only. Use when
  the user mentions hybrid local, Colima, Minikube, Argo product-apps, Create
  Product stuck, empty catalog, Open Product, /product-ui, NodePort forwards,
  or 16GB Mac Paxo setup.
---

# Paxo hybrid local

## Working window (this machine)

- **Stay on this Mac / Cursor account through 23 Oct 2026** for daily hybrid work.
- Treat git + this skill as source of truth; commit hybrid fixes as they land.
- **On/after 24 Oct 2026**: move via `CURSOR_ACCOUNT_TRANSFER.md` + Desktop zip from `export-cursor-paxo-pack.sh` (push all repos first).
- Until cutover: prefer `bash paxo/scripts/start-hybrid-stack.sh` each day; do not put core into Argo.

## Architecture (do not collapse)

| Layer | Runs | Apps |
|-------|------|------|
| Docker Compose | `paxo/local-hybrid/docker-compose.signup.yml` | identity, PMS, gateway, Keycloak, MySQL |
| Minikube + Argo | `k8/product-apps.yaml` → `k8/generated-apps` | Customer product FE/BE only |
| Host | `ng serve` + port-forwards | Paxo UI `:4300`, product NodePorts |

**Do not** put full core (identity/PMS/foundry) into Argo on a 16GB Mac.

**Foundry** is optional and not in the default hybrid compose.

## Ports

| Service | Port |
|---------|------|
| Paxo UI (`ng serve`) | `4300` |
| API gateway | `8085` |
| Identity | `8087` |
| PMS | `8088` |
| Keycloak | `8080` |
| MySQL (host) | `3307` |
| Argo UI (typical) | `8081` |
| Product FE NodePort (example) | `32100` (via forward) |
| Product BE NodePort (example) | `32400` (via forward) |

Open Product uses **NodePort** (`PROVISIONING_BROWSER_URL_MODE=nodeport`), e.g. `http://127.0.0.1:32100/`.

## Start order

```bash
export DOCKER_HOST=unix://${HOME}/.colima/default/docker.sock

# 1) Colima + Minikube must already be running
# 2) Core
cd paxo/local-hybrid && docker compose -f docker-compose.signup.yml up -d

# 3) Argo product-apps (once)
kubectl apply -f paxo/k8/product-apps.yaml

# 4) Product NodePort forwards
bash paxo/scripts/start-hybrid-product-forwards.sh

# 5) Paxo UI
cd paxo_frontend && npx ng serve --port 4300 --host 0.0.0.0 --proxy-config proxy.conf.js
```

Or: `bash paxo/scripts/start-hybrid-stack.sh`

## PMS ↔ cluster

PMS (Compose) talks to Minikube via mounted kubeconfig and `host.docker.internal`, often with insecure TLS skip for local API. Without kubectl inside PMS, Create Product sticks ~80% (Argo apps not applied).

## Frontend proxy (Angular 20 / Vite)

- `paxo_frontend/proxy.conf.js` must use **object-form** keys (`'/product-ui': { ... }`).
- Array entries with `context: (fn)` are **silently skipped** by `@angular/build`.
- Prefer Vite `rewrite` over webpack function `pathRewrite`.
- `/product-ui/{realm}/{product}/` rewrites to NodePort; HTML `<base href="/">` is rewritten to the product-ui prefix so assets load.
- ng serve dies often if the process is killed — restart it; Open Product NodePort still works if forwards are up.

## Catalog / home

- Home showcase list must stay **DB-fast** (no blocking kubectl on list).
- Empty catalog: realm filter / SA / sync — check PMS logs, not Argo core apps.
- Stuck Create Product: generated Argo apps missing, wrong image (CI sed hitting wait-for-postgres), or PMS kubectl broken.

## Images

Prefer `paxarisdocker/*` on Docker Hub. After recreate, restore secrets and re-apply `product-apps` (not full core `argocd-app`).

## Debug map

| Symptom | Check |
|---------|--------|
| Argo missing PMS/identity | Expected — core is Compose |
| Open Product connection refused on `:4300` | Restart `ng serve`; prefer NodePort URL |
| Open Product blank / Paxo SPA | Proxy not loaded or base href; forwards down |
| Create Product ~80% | PMS kubectl + `k8/generated-apps` + Argo sync |
| Home loading forever | Showcase list blocked on kubectl/gateway |

## More detail

- Setup checklist: [setup.md](setup.md)
- Cursor account transfer: see repo root `CURSOR_ACCOUNT_TRANSFER.md`
