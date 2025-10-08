#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Stopping Docker services (MariaDB + Redis)..."
docker compose down

echo "Done."

