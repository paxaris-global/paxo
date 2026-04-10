# Paxo Kubernetes + ngrok

## Run full stack with ngrok

Prerequisites:
- Minikube is running and your workloads are deployed in Kubernete.
- `kubectl` and `ngrok` are installed.
- ngrok authtoken is configured (`ngrok config add-authtoken <token>`).

From this folder, run:

```bash
./scripts/start-ngrok.sh
```

Use a custom short domain label (example):

```bash
./scripts/start-ngrok.sh paxarisglobal-api
```

This resolves to `https://paxarisglobal-api.ngrok-free.app` by default.
If your ngrok account uses a different suffix, set it before running:

```bash
NGROK_DOMAIN_SUFFIX=ngrok-free.dev ./scripts/start-ngrok.sh paxarisglobal-api
```

This starts:
- `kubectl port-forward svc/paxo-frontend 4200:80`
- `ngrok` tunnel for frontend (configured in `ngrok/ngrok.yml`)

Why one tunnel is enough:
- Frontend Nginx proxies `/identity`, `/project`, and `/gateway` to `api-gateway` inside Kubernetes.
- So the single frontend ngrok URL gives access to the full stack.

To stop all helper processes:

```bash
./scripts/stop-ngrok.sh
```