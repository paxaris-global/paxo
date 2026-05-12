#!/usr/bin/env bash
set -euo pipefail

echo "Stopping all services..."

pkill -f "kubectl port-forward svc/paxo-frontend" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/keycloak" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/api-gateway" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/identity-service" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/product-management-service" >/dev/null 2>&1 || true
pkill -f "kubectl port-forward svc/jaeger" >/dev/null 2>&1 || true
pkill -f "port-forward.*svc/argocd-server" >/dev/null 2>&1 || true
pkill -f "ngrok" >/dev/null 2>&1 || true

echo "All services stopped."
