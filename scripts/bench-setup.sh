#!/usr/bin/env bash
# Initialize a local bench for ERPNext using Dockerized DB/Redis
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

if ! command -v bench >/dev/null 2>&1; then
  echo "bench CLI chưa có trong .venv. Chạy scripts/bootstrap.sh" >&2
  exit 1
fi

# Helper: wait for TCP host:port
wait_for_tcp() {
  local host="$1"; local port="$2"; local timeout="${3:-60}"; local start end
  echo "Đợi ${host}:${port} sẵn sàng (timeout ${timeout}s)..."
  start=$(date +%s)
  while true; do
    if command -v nc >/dev/null 2>&1; then
      if nc -z "$host" "$port" 2>/dev/null; then
        echo "Đã kết nối được ${host}:${port}."; return 0
      fi
    else
      python3 - <<PY 2>/dev/null && { echo "Đã kết nối được ${host}:${port}."; return 0; } || true
import socket
s=socket.socket()
s.settimeout(1)
try:
  s.connect(("$host", int("$port")))
  s.close()
  raise SystemExit(0)
except Exception:
  raise SystemExit(1)
PY
    fi
    end=$(date +%s)
    if [ $((end-start)) -ge "$timeout" ]; then
      echo "Timeout chờ ${host}:${port}." >&2
      return 1
    fi
    sleep 2
  done
}

BENCH_DIR="bench"

# 1) bench init
if [ ! -d "$BENCH_DIR" ]; then
  echo "Tạo bench tại $BENCH_DIR (Frappe ${FRAPPE_BRANCH})..."
  bench init "$BENCH_DIR" --frappe-branch "$FRAPPE_BRANCH" --python "$(which python3)" --skip-assets
else
  echo "Bỏ qua: Thư mục $BENCH_DIR đã tồn tại."
fi

cd "$BENCH_DIR"

# 1.1) Configure Redis endpoints globally before site creation to avoid MISCONF
echo "Cấu hình Redis (global common_site_config.json) trước khi tạo site..."
bench set-config -g redis_cache "$REDIS_CACHE"
bench set-config -g redis_queue "$REDIS_QUEUE"
bench set-config -g redis_socketio "$REDIS_SOCKETIO"

# 1.2) Prevent bench from starting embedded Redis servers (use Docker Redis)
if [ -f Procfile ]; then
  echo "Vô hiệu hóa redis_cache/redis_queue/redis_socketio trong Procfile..."
  # macOS sed requires a backup suffix or empty string
  sed -i '' -e 's/^redis_cache:/# redis_cache: (disabled, using Docker)/' \
            -e 's/^redis_queue:/# redis_queue: (disabled, using Docker)/' \
            -e 's/^redis_socketio:/# redis_socketio: (disabled, using Docker)/' Procfile || true
fi

# 2) Get ERPNext app if not present
if [ ! -d apps/erpnext ]; then
  echo "Tải ERPNext (branch ${ERPNEXT_BRANCH})..."
  bench get-app --branch "$ERPNEXT_BRANCH" erpnext https://github.com/frappe/erpnext
else
  echo "Bỏ qua: apps/erpnext đã tồn tại."
fi

# 3) Create site if missing
SITES_DIR="sites"
SITE_PATH="$SITES_DIR/$SITE_NAME"
if [ ! -d "$SITE_PATH" ]; then
  # Wait for MariaDB readiness
  wait_for_tcp "$DB_HOST" "$DB_PORT" 120
  echo "Tạo site ${SITE_NAME}..."
  bench new-site "$SITE_NAME" \
    --admin-password "$ADMIN_PASSWORD" \
    --mariadb-root-password "$DB_ROOT_PASSWORD" \
    --db-host "$DB_HOST" \
    --db-port "$DB_PORT" \
    --no-mariadb-socket
else
  echo "Phát hiện thư mục site ${SITE_NAME}. Kiểm tra tính toàn vẹn..."
  if ! bench --site "$SITE_NAME" list-apps >/dev/null 2>&1; then
    echo "Site có thể tạo dở dang. Thực hiện drop-site và tạo lại..."
    wait_for_tcp "$DB_HOST" "$DB_PORT" 120
    bench drop-site "$SITE_NAME" --root-password "$DB_ROOT_PASSWORD" --force
    echo "Tạo lại site ${SITE_NAME}..."
    bench new-site "$SITE_NAME" \
      --admin-password "$ADMIN_PASSWORD" \
      --mariadb-root-password "$DB_ROOT_PASSWORD" \
      --db-host "$DB_HOST" \
      --db-port "$DB_PORT" \
      --no-mariadb-socket
  else
    echo "Bỏ qua: Site ${SITE_NAME} có vẻ hợp lệ."
  fi
fi

# 4) Global config: point to Docker Redis
echo "Cấu hình Redis (global common_site_config.json) trỏ về Docker..."
bench set-config -g redis_cache "$REDIS_CACHE"
bench set-config -g redis_queue "$REDIS_QUEUE"
bench set-config -g redis_socketio "$REDIS_SOCKETIO"

# 5) Ensure DB port in site_config if non-default
if [ "$DB_PORT" != "3306" ]; then
  echo "Thiết lập db_port=${DB_PORT} cho site ${SITE_NAME}..."
  bench --site "$SITE_NAME" set-config db_port "$DB_PORT"
fi

# 6) Install ERPNext
if ! bench --site "$SITE_NAME" list-apps | grep -q '^erpnext$'; then
  echo "Cài đặt ứng dụng ERPNext vào site ${SITE_NAME}..."
  bench --site "$SITE_NAME" install-app erpnext
else
  echo "Bỏ qua: erpnext đã được cài cho site ${SITE_NAME}."
fi

# 7) Developer conveniences for this site
echo "Bật developer_mode và host_name cho ${SITE_NAME}..."
bench --site "$SITE_NAME" set-config developer_mode 1
bench --site "$SITE_NAME" set-config host_name "$SITE_NAME"

# 8) Set default site for localhost access without host header
bench set-default-site "$SITE_NAME"

echo "Hoàn tất bench setup. Gợi ý thêm dòng sau vào /etc/hosts nếu chưa có:\n  127.0.0.1 ${SITE_NAME}"
