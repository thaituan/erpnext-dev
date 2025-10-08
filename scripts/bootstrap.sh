#!/usr/bin/env bash
# Bootstrap local toolchain for Frappe/ERPNext hybrid dev on macOS
# - Installs Python via pyenv (fallback to system Python)
# - Sets up a local .venv and installs frappe-bench
# - Installs Node LTS via nvm and Yarn
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
  echo "Missing .env in project root. Copy and adjust it first." >&2
  exit 1
fi

# Load .env
set -a; source .env; set +a

command_exists() { command -v "$1" >/dev/null 2>&1; }

# 1) Ensure Homebrew exists (optional but recommended)
if ! command_exists brew; then
  echo "Homebrew không có sẵn. Cài đặt theo hướng dẫn: https://brew.sh/"
  echo "Bạn có thể tiếp tục nếu đã có pyenv/nvm theo cách khác."
fi

# 2) Python via pyenv
if command_exists pyenv; then
  echo "Installing Python ${PYTHON_VERSION} via pyenv if missing..."
  if ! pyenv versions --bare | grep -qx "${PYTHON_VERSION}"; then
    # Build deps (only if brew exists)
    if command_exists brew; then
      brew update || true
      brew install openssl readline sqlite3 xz zlib bzip2 || true
    fi
    CFLAGS="-I$(xcrun --show-sdk-path)/usr/include" pyenv install -s "${PYTHON_VERSION}"
  fi
  PY_BIN="$(pyenv root)/versions/${PYTHON_VERSION}/bin/python3"
  if [ ! -x "$PY_BIN" ]; then
    echo "Không tìm thấy Python ${PYTHON_VERSION}. Kiểm tra pyenv." >&2
    exit 1
  fi
else
  echo "pyenv không có sẵn. Sẽ dùng python3 hệ thống. Khuyến nghị cài pyenv để khớp version."
  PY_BIN="$(command -v python3 || true)"
  if [ -z "$PY_BIN" ]; then
    echo "Không tìm thấy python3 trong hệ thống." >&2
    exit 1
  fi
fi

# 3) Create local virtualenv
if [ ! -d .venv ]; then
  echo "Tạo virtualenv tại .venv ..."
  "$PY_BIN" -m venv .venv
fi
source .venv/bin/activate
python -m pip install --upgrade pip wheel setuptools

# 4) Install bench CLI locally in this venv
if ! .venv/bin/bench --help >/dev/null 2>&1; then
  echo "Cài đặt frappe-bench..."
  pip install "frappe-bench<6"  # bench 5.x for Frappe v15/v16
fi

# 5) Install Node via nvm and Yarn
if [ -z "${NVM_DIR:-}" ]; then
  export NVM_DIR="$HOME/.nvm"
fi
if [ ! -s "$NVM_DIR/nvm.sh" ]; then
  echo "Cài đặt nvm (Node Version Manager)..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi
# shellcheck disable=SC1090
source "$NVM_DIR/nvm.sh"

echo "Cài đặt Node ${NODE_MAJOR}.x qua nvm..."
nvm install ${NODE_MAJOR}
nvm use ${NODE_MAJOR}

if ! command_exists yarn; then
  echo "Cài đặt Yarn..."
  npm install -g yarn@1
fi

# 6) wkhtmltopdf (khuyến nghị cho in ấn PDF)
if ! command_exists wkhtmltopdf; then
  echo "Gợi ý: cài wkhtmltopdf (patch qt) để in PDF:"
  echo "  brew install --cask wkhtmltopdf"
fi

echo "Bootstrap hoàn tất."

