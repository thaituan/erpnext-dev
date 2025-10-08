#!/usr/bin/env bash
# Start the local bench in dev mode
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "Missing .env in project root." >&2
  exit 1
fi

# Load env and activate venv
set -a; source .env; set +a
if [ ! -d .venv ]; then
  echo ".venv chưa tồn tại. Hãy chạy scripts/bootstrap.sh trước." >&2
  exit 1
fi
source .venv/bin/activate

# Ensure nvm + Node available for asset watchers
if [ -z "${NVM_DIR:-}" ]; then
  export NVM_DIR="$HOME/.nvm"
fi
if [ -s "$NVM_DIR/nvm.sh" ]; then
  # shellcheck disable=SC1090
  source "$NVM_DIR/nvm.sh"
  nvm install ${NODE_MAJOR} >/dev/null 2>&1 || true
  nvm use ${NODE_MAJOR} >/dev/null 2>&1 || true
  # Prepend active Node bin to PATH to ensure child processes use it
  if [ -n "${NVM_BIN:-}" ]; then
    export PATH="$NVM_BIN:$PATH"
  else
    # Fallback: derive from nvm which
    NODE_PATH_DIR="$(dirname "$(nvm which ${NODE_MAJOR} 2>/dev/null || command -v node)")"
    export PATH="$NODE_PATH_DIR:$PATH"
  fi
fi

cd bench

echo "Node version: $(node -v 2>/dev/null || echo 'node not found')"
echo "Khởi chạy bench development server..."
# Bind to all interfaces to allow access via erp.local
bench start
