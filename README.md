# ERPNext Hybrid Dev trên macOS (Docker cho DB/Redis + Bench trên host)

Lưu ý: Bạn đề cập "hyperid" — ở đây mình hiểu là "hybrid" (kết hợp Docker và setup code truyền thống). Repo này dựng sẵn môi trường phát triển ERPNext theo cách đó: dùng Docker cho MariaDB/Redis, còn bench + mã nguồn chạy trực tiếp trên máy để code/customize nhanh, build asset mượt và debug tiện.

## Tổng quan
- Docker chạy: MariaDB 10.6 và 3 Redis (cache/queue/socketio)
- Host chạy: Python virtualenv + bench CLI, code Frappe/ERPNext local
- Bạn có thể chỉnh sửa app trong thư mục bench/apps và thấy thay đổi ngay khi `bench start` đang chạy

## Yêu cầu
- macOS + Xcode Command Line Tools: `xcode-select --install`
- Docker Desktop for Mac
- Homebrew (khuyến nghị): https://brew.sh/

## Cấu hình nhanh
1) Chỉnh `.env` theo nhu cầu (branch, tên site, mật khẩu):
   - FRAPPE_BRANCH, ERPNEXT_BRANCH (vd: version-15 hoặc version-16)
   - SITE_NAME (vd: erp.local)
   - ADMIN_PASSWORD (mật khẩu Administrator)
   - DB_ROOT_PASSWORD (root pwd cho MariaDB container)
   - PYTHON_VERSION (vd: 3.11.9), NODE_MAJOR (18 cho v15, 20 cho v16)

2) Cài công cụ nền tảng (pyenv/nvm/bench) và tạo virtualenv:

```bash
./scripts/bootstrap.sh
```

3) Khởi động Docker services (MariaDB/Redis):

```bash
./scripts/dev-start.sh
```

4) Tạo bench, tải ERPNext và khởi tạo site:

```bash
./scripts/bench-setup.sh
```

5) Thêm host mapping cho domain dev (nếu dùng `erp.local`):

```bash
echo "127.0.0.1 erp.local" | sudo tee -a /etc/hosts
```

6) Chạy server dev:

```bash
./scripts/bench-start.sh
```

- Truy cập: http://erp.local:8000 (hoặc http://localhost:8000)
- Đăng nhập: Administrator / ADMIN_PASSWORD trong `.env`

## Cấu trúc repo
- `.env`: phiên bản, thông số DB/Redis, site, toolchain
- `docker-compose.yml`: các dịch vụ MariaDB + Redis
- `scripts/`:
  - `bootstrap.sh`: cài pyenv/nvm, tạo .venv, cài bench
  - `dev-start.sh` | `dev-stop.sh`: bật/tắt Docker services
  - `bench-setup.sh`: init bench, get-app ERPNext, new-site, install-app
  - `bench-start.sh`: chạy server dev (watchers)
- `bench/`: tạo bởi bench init (sau khi chạy setup)

## Phát triển/customize
- Tạo app mới:

```bash
source .venv/bin/activate
cd bench
bench new-app my_app
bench --site $SITE_NAME install-app my_app
```

- Sửa Python/JS/Doctype trong `bench/apps/...`; `bench start` sẽ tự build/watch
- Build tay khi cần:

```bash
cd bench
bench build
```

- Migrate sau khi chỉnh schema:

```bash
cd bench
bench --site $SITE_NAME migrate
```

## Mẹo và lưu ý
- Node: v15 thường ổn với Node 18; v16 dùng Node 20. Chỉnh `NODE_MAJOR` trong `.env`.
- wkhtmltopdf (in PDF): `brew install --cask wkhtmltopdf` (bản patched là tốt nhất)
- Nếu cổng 3307 đang dùng, đổi `DB_PORT` trong `.env` rồi chạy lại `./scripts/dev-start.sh`
- Port Redis cố định: 6379/6380/6381
- Nếu pip build gói native lỗi (vd: mysqlclient), đảm bảo đã cài toolchain qua Homebrew (openssl, zlib, bzip2...). Script đã cố gắng chuẩn bị sẵn.

## Sự cố thường gặp
- Kết nối DB lỗi: đảm bảo Docker đang chạy và cổng `DB_PORT` trỏ đúng; xem `docker compose ps`
- Redis không kết nối: kiểm tra các URL trong `.env` và `bench set-config -g ...` đã chạy qua script
- Lỗi Node/yarn: mở terminal mới sau khi bootstrap để nạp NVM, hoặc `source "$HOME/.nvm/nvm.sh" && nvm use`
- Chậm khi build asset: dùng Node đúng version, giữ Docker Desktop cập nhật

## Nâng cấp/Update
- Cập nhật mã ERPNext/Frappe theo branch trong `.env`:

```bash
source .venv/bin/activate
cd bench
bench update --reset
```

- Hoặc cập nhật riêng app erpnext:

```bash
cd bench/apps/erpnext
git fetch --all
git checkout <branch>
git pull
cd ../../
bench build
bench --site $SITE_NAME migrate
```

## Gỡ dịch vụ

```bash
./scripts/dev-stop.sh
```

Dữ liệu DB/Redis nằm trong volumes Docker, không mất khi stop. Xóa hoàn toàn:

```bash
docker compose down -v
```

