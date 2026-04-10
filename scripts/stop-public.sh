#!/usr/bin/env bash
set -euo pipefail

echo "Stopping public access..."

pkill -f "ngrok http 4200" >/dev/null 2>&1 || true

echo "Public access stopped."
