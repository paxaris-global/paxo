#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/.ngrok-runtime"

echo "Stopping backend public access..."

pkill -f "kubectl port-forward svc/paxo-frontend" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/keycloak" >/dev/null 2>&1 || true
pkill -f "ngrok http 8085" >/dev/null 2>&1 || true
pkill -f "ngrok http 4200" >/dev/null 2>&1 || true
pkill -f "ngrok http 8087" >/dev/null 2>&1 || true
pkill -f "ngrok http 8088" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/api-gateway" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/identity-service" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/product-management-service" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/jaeger" >/dev/null 2>&1 || true

echo "Backend public access stopped."
