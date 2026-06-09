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

### GitHub credentials (Create Product / provisioning)

`product-management-service` uses a **GitHub Personal Access Token** (`ghp_...`), **not** your GitHub login password and **not** the Mac Keychain.

1. In the browser (logged into GitHub): [Create classic PAT](https://github.com/settings/tokens/new) with scopes **`repo`**, **`admin:org`**, **`workflow`**. If your org uses SSO, click **Configure SSO** → authorize **PaxarisGlobal**.
2. Sync to the cluster (paste token when prompted — nothing is your account password):

```bash
chmod +x scripts/sync-github-credentials.sh
./scripts/sync-github-credentials.sh --prompt
```

Or put `GITHUB_TOKEN=ghp_...` in `paxo/.env` and run `./scripts/sync-github-credentials.sh`.

If Create Product fails with `401 Bad credentials`, create a **new** PAT and run the script again.

### Reach the UI/API from your laptop (cluster already running)

Pods are already running in Kubernetes (Argo CD). Choose **one** access mode:

**Recommended — NodePort URLs (same ports as Kubernetes / Argo manifests):**

```bash
./scripts/start-minikube-access.sh
# Open http://127.0.0.1:32000  (paxo-frontend Service NodePort)
```

Binds `127.0.0.1` to the cluster Service ports declared in `k8/` (no `ng serve`). Stop with `./scripts/stop-minikube-access.sh`. Do not run `start-local-access.sh` at the same time.

**Alternative — kubectl port-forward (dev convenience):**

```bash
./scripts/start-local-access-foreground.sh
# Open http://localhost:4200
```

That **port-forwards** to the same Argo-deployed pods—not `ng serve`.

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




Keycloak: http://192.168.49.2:32080
Identity Service: http://192.168.49.2:32087
Product Management Service: http://192.168.49.2:32088
Jaeger UI: http://192.168.49.2:31686
Jaeger OTLP gRPC: http://192.168.49.2:30417
Jaeger OTLP HTTP: http://192.168.49.2:30418
API Gateway: http://api-gateway.default.svc.cluster.local:8085
Paxo Frontend: http://paxo-frontend.default.svc.cluster.local
Python Frontend: http://python-frontend.default.svc.cluster.local
Python Foundry API: http://python-foundry-api.default.svc.cluster.local:8000
Generated Frontend: http://finaltest36-admin-backend-test-frontend.default.svc.cluster.local
Generated Backend: http://finaltest36-admin-backend-test-backend.default.svc.cluster.local:8080
MySQL: mysql://mysql.default.svc.cluster.local:3306
Python Foundry PostgreSQL: postgresql://python-foundry-postgres.default.svc.cluster.local:5432
Python Foundry Redis: redis://python-foundry-redis.default.svc.cluster.local:6379
Argo CD HTTP: http://argocd-server.argocd.svc.cluster.local
Argo CD HTTPS: https://argocd-server.argocd.svc.cluster.local