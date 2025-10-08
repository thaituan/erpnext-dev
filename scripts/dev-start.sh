#!/usr/bin/env bash
set -euo pipefail

# Start Docker services for DB/Redis
cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "Missing .env in project root. Copy and adjust it first." >&2
  exit 1
fi

export $(grep -v '^#' .env | xargs)

echo "Starting Docker services (MariaDB + Redis)..."
docker compose up -d

echo "Services status:"
docker compose ps

echo "Done. MariaDB listening on ${DB_HOST}:${DB_PORT}, Redis on 6379/6380/6381"

