# Paxo

## Kubernetes + Argo CD (how the stack runs)

This repo is the **GitOps source** for the Paxo platform. **Do not rely on `ng serve`** for production-style runs: frontends and backends are **Docker images** deployed as Kubernetes **Deployments**, synced by **Argo CD**.

### Argo CD application

- **Application name:** `paxo-app` (namespace `argocd`)
- **Source:** `https://github.com/paxaris-global/paxo.git`, branch **`main`**, path **`k8/`** (recursive)
- **Destination:** cluster `https://kubernetes.default.svc`, namespace **`default`**
- **Sync:** automated prune + self-heal (`k8/argocd-app.yaml`)

Bootstrap Argo once (if `paxo-app` is not already installed):

```bash
kubectl apply -n argocd -f k8/argocd-app.yaml
```

**Argo CD UI in Chrome (local):** run `./scripts/start-argocd-ui.sh` and open **`http://127.0.0.1:8081`** (plain HTTP; no TLS prompt). The cluster is configured with `server.insecure=true` and `argocd-cm` `url` for this dev flow. If the UI was opened with **`https://` before, switch to **`http://`**.

### What `paxo-app` deploys (manifests under `k8/`)

| Area | Resources |
|------|-----------|
| Edge / UI | `api-gateway`, `paxo-frontend`, `python-frontend` (Python Foundry UI) |
| Identity | `identity-service`, `keycloak`, `mysql` |
| Products | `product-management-service` |
| Observability | `jaeger` |
| Python Foundry | `python-foundry-stack.yaml` (API, worker, Postgres, Redis) |
| Optional demos | `finaltest36-*` deployments |
| Child apps | `finaltest35-*` Application CRs → separate repos (if enabled) |

Images come from Docker Hub (e.g. `devopspaxarisglobalrepo/...`), tagged by **GitHub Actions** in `paxaris-global/paxo` (central image builder + manifest updates on **`main`**).

### Day-to-day workflow (no `ng serve`)

1. **Change code** in the service repo (e.g. `paxo_frontend`, `api-gateway`).
2. **CI** builds and pushes the image, then updates the image field in **`paxo/k8/*.yaml`** on **`main`** (see `.github/workflows/build_and_push.yml`).
3. **Argo CD** detects the commit and **syncs** the cluster.

To run everything **inside Kubernetes** after manifests exist: ensure **`dockerhub-secret`** exists in **`default`** (for private pulls), then let **Argo** apply **`main`**.

### Reach the UI/API from your laptop (cluster already running)

Kubernetes **Services** are **ClusterIP** by default (no public URL in-git). For local browsing without `ng serve`:

```bash
./scripts/start-local-access.sh
```

That **port-forwards** to pods already deployed by Argo (frontend `:4200`, gateway `:8085`, etc.). You are still hitting **the same images** Argo deployed—not a dev server.

If another local project already uses one of those ports, override only the host-facing port:

```bash
PAXO_FRONTEND_LOCAL_PORT=4300 PAXO_GATEWAY_LOCAL_PORT=18085 ./scripts/start-local-access.sh
```

Available overrides are defined in `scripts/local-ports.sh`: `PAXO_FRONTEND_LOCAL_PORT`, `PAXO_KEYCLOAK_LOCAL_PORT`, `PAXO_GATEWAY_LOCAL_PORT`, `PAXO_IDENTITY_LOCAL_PORT`, `PAXO_PRODUCT_LOCAL_PORT`, `PAXO_PYTHON_FRONTEND_LOCAL_PORT`, and `PAXO_JAEGER_LOCAL_PORT`.

---

## Optional: public URL with ngrok

Prerequisites: Minikube/cluster running, workloads deployed, `kubectl` + `ngrok` configured.

```bash
./scripts/start-ngrok.sh
# optional label:
./scripts/start-ngrok.sh paxarisglobal-api
```

Stop:

```bash
./scripts/stop-ngrok.sh
```

Frontend nginx proxies `/identity`, `/project`, `/gateway` to `api-gateway`, so one frontend tunnel can expose the stack.

---

## Legacy: Docker Compose

Some developers still use **`docker-compose.yml.backup`** for an all-in-one Docker setup on the host. The **recommended** path for Paxaris is **Kubernetes + Argo CD + images on `main`** as described above.
