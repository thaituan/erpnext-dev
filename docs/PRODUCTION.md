# Triển khai ERPNext Production

Tài liệu này hướng dẫn triển khai ERPNext/Frappe lên môi trường production theo 2 cách:
- A) Dùng Docker stack chính thức (frappe_docker) – khuyến nghị.
- B) Dùng bare-metal (bench + nginx + supervisor/systemd) – phù hợp single-host đơn giản.

Ngoài ra có checklist bảo mật, sao lưu/khôi phục, nâng cấp, scale và xử lý sự cố.

---

## A) Production với frappe_docker (khuyến nghị)
Tham khảo: https://github.com/frappe/frappe_docker

Ưu điểm
- Tách biệt dịch vụ: traefik/nginx, backend (gunicorn), socketio, workers, scheduler, redis, mariadb, queue, cron…
- Dễ mở rộng, backup/restore chuẩn, quản lý qua Docker Compose/Swarm/K8s.

Yêu cầu
- Máy chủ Linux (Ubuntu 22.04/24.04 khuyến nghị), CPU >= 4 vCPU, RAM >= 8 GB (tùy phụ tải)
- Docker + Docker Compose v2, DNS domain hợp lệ

Các bước tổng quát
1) Chuẩn bị máy chủ và DNS
- Tạo VPS/VM, mở firewall cho 80/443 (HTTP/HTTPS)
- Trỏ A/AAAA record domain về IP máy chủ (vd: erp.yourdomain.com)

2) Cài Docker và Compose
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Đăng xuất/đăng nhập lại
sudo apt-get install -y docker-compose-plugin
```

3) Lấy bộ cấu hình frappe_docker
```bash
git clone https://github.com/frappe/frappe_docker.git
cd frappe_docker
cp example.env .env
# Chỉnh .env: phiên bản, domain, email ACME (Let's Encrypt), mật khẩu admin, DB root pwd...
```

4) Khởi chạy reverse proxy và core services
- frappe_docker sử dụng Traefik làm reverse proxy (auto TLS Let's Encrypt)
```bash
# Ví dụ (tùy cấu trúc repo, tên compose)
docker compose -f compose.yaml -f overrides/compose.traefik.yaml up -d
```

5) Tạo bench container, site và cài ERPNext
```bash
# Vào container bench
docker compose exec backend bash
# Trong container:
bench new-site erp.yourdomain.com \
  --admin-password "<ADMIN_PASSWORD>" \
  --mariadb-root-password "<DB_ROOT_PASSWORD>"
bench get-app --branch version-15 erpnext https://github.com/frappe/erpnext
bench --site erp.yourdomain.com install-app erpnext
exit
```

6) Cấu hình route/TLS cho domain
- Theo mẫu labels Traefik hoặc file compose override của frappe_docker, ánh xạ host rule về service web.
- Tự động lấy chứng chỉ Let's Encrypt nhờ Traefik (cần cấu hình email ACME trong .env).

7) Kiểm tra truy cập
- Mở https://erp.yourdomain.com
- Đăng nhập: Administrator / ADMIN_PASSWORD

8) Dữ liệu và backup (docker volume)
- DB (MariaDB), files (public/private) được map ra volumes.
- Dùng container backup hoặc cron bên ngoài để chạy mysqldump + tar files.

Mẹo triển khai
- MariaDB: dùng 10.6 (khuyến nghị cho v15/v16), RAM buffer pool phù hợp.
- Redis: bật AOF/RDB theo nhu cầu durability (trong production nên bật persistence).
- SMTP: cấu hình trong site_config.json (hoặc giao diện System Settings).

---

## B) Production bare-metal (bench + nginx + supervisor)
Phù hợp máy đơn giản, ít container. Không nên dùng dev server; dùng gunicorn/nginx/supervisor.

Yêu cầu
- Ubuntu 22.04/24.04, Python 3.11, Node 18 (v15) hoặc Node 20 (v16), Yarn 1
- wkhtmltopdf (patched) để in PDF
- MariaDB 10.6 (khuyến nghị), Redis 6.x

Các bước tổng quát
1) Cài đặt dependency
```bash
sudo apt-get update
sudo apt-get install -y python3-pip python3-venv python3-dev \
  libffi-dev libssl-dev wkhtmltopdf \
  mariadb-server mariadb-client redis-server \
  nodejs npm
npm install -g yarn@1
```

2) Tạo user và bench
```bash
sudo adduser frappe
sudo usermod -aG sudo frappe
sudo su - frappe

python3 -m venv ~/bench-venv
source ~/bench-venv/bin/activate
pip install --upgrade pip wheel setuptools
pip install "frappe-bench<6"
bench init ~/frappe-bench --frappe-branch version-15
cd ~/frappe-bench
bench get-app --branch version-15 erpnext https://github.com/frappe/erpnext
bench new-site erp.yourdomain.com \
  --admin-password "<ADMIN_PASSWORD>" \
  --mariadb-root-password "<DB_ROOT_PASSWORD>"
bench --site erp.yourdomain.com install-app erpnext
```

3) Nginx + Supervisor (hoặc Systemd)
- bench có tiện ích setup production (yêu cầu quyền root):
```bash
# quay lại root
exit
sudo bench setup production frappe
# Lệnh này sẽ tạo file cấu hình nginx và supervisor cho web, socketio, workers, schedule
```
- Kiểm tra service và reload nginx/supervisor.

4) TLS (Let's Encrypt)
```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d erp.yourdomain.com
```

5) Cấu hình Redis production
- Redis queue/cache/socketio: có thể dùng 1 instance (nhiều DB) hoặc tách 3 instance.
- Bật persistence (AOF hoặc RDB), cấu hình bảo mật (requirepass nếu đặt trong mạng công cộng), giới hạn memory policies.

6) Kiểm tra
- https://erp.yourdomain.com → đăng nhập
- Kiểm tra workers, scheduler, email outbound, PDF print.

---

## Cấu hình quan trọng trong production
- Database (MariaDB 10.6 khuyến nghị)
  - Charset/collation: utf8mb4, utf8mb4_unicode_ci
  - Tuning: innodb_buffer_pool_size ~50–70% RAM, innodb_log_file_size, max_connections phù hợp tải
  - Sao lưu: mysqldump theo lịch + binlog (nếu cần PITR)
- Redis
  - Bật persistence (appendonly yes hoặc RDB), stop-writes-on-bgsave-error no (tùy nhu cầu)
  - Giới hạn maxmemory và eviction policy nếu cần
- Web
  - Không dùng dev server; dùng gunicorn/nginx hoặc stack docker official
  - Bật gzip/brotli, http2, HSTS, CORS hợp lệ
- Email
  - SMTP cho thông báo hệ thống (System Settings → Email Domain/Account)
- Bảo mật
  - Firewall (ufw) mở 80/443; đóng port admin không cần thiết
  - Fail2ban (ngăn brute-force)
  - Mật khẩu mạnh, 2FA cho Administrator
  - Giới hạn upload size nếu cần

---

## Sao lưu và khôi phục
Backup tối thiểu gồm: database + files (public/private) + site_config.json

Ví dụ (bare-metal):
```bash
# DB
mysqldump -u root -p --single-transaction --quick --lock-tables=false <dbname> | gzip > backup.sql.gz
# Files
cd ~/frappe-bench/sites
tar czf files.tgz erp.yourdomain.com/public erp.yourdomain.com/private
# Config
cp erp.yourdomain.com/site_config.json site_config.json.bak
```

Khôi phục:
```bash
# Tạo site trống trước (cùng tên), sau đó nhập DB và thay files
gunzip < backup.sql.gz | mysql -u root -p <dbname>
tar xzf files.tgz -C ~/frappe-bench/sites/
```

Trên docker: map volumes hoặc dùng container backup scripts; đẩy ra S3 bằng rclone/cron.

Lịch backup:
- Full hàng ngày + giữ 7–14 bản
- Sao lưu off-site (S3/Wasabi) + kiểm tra khôi phục định kỳ

---

## Nâng cấp/Update
- Tạo môi trường staging để test trước khi lên production
- Với bare-metal:
```bash
cd ~/frappe-bench
bench update --reset
bench --site erp.yourdomain.com migrate
bench build
```
- Với docker: pull image mới theo tag/branch, chạy migrate từ container backend.

---

## Scaling
- Web: tăng worker (gunicorn) + reverse proxy; đặt cạnh CDN cho static
- SocketIO: scale nhiều replica; sticky sessions qua Traefik/nginx
- Worker: nhân bản workers theo queue
- DB: tách sang RDS/Cloud SQL; tune IOPS; read replicas (nếu cần)
- Redis: cluster/sentinel (nếu yêu cầu HA)

---

## Giám sát và logging
- Metrics: node-exporter + Prometheus/Grafana
- Logs: Loki/ELK; theo dõi nginx, gunicorn, workers
- Cảnh báo: uptime checks (StatusCake/Healthchecks), email/slack

---

## Xử lý sự cố nhanh
- 502/504: kiểm tra nginx/proxy -> web backend (gunicorn) có chạy không
- Lỗi migrate: `bench --site <site> migrate` + kiểm tra migration conflicts
- Redis lỗi MISCONF: kiểm tra persistence/quyền ghi, cấu hình stop-writes-on-bgsave-error
- PDF lỗi: đảm bảo wkhtmltopdf bản patched
- Chậm/treo: EXPLAIN query nặng, tăng indexes, thêm caching, tăng worker concurrency

---

## Khuyến nghị cuối
- Production nên dùng MariaDB 10.6 và Redis persistence
- Dùng frappe_docker cho triển khai chuẩn/scale dễ
- Có staging và plan backup/khôi phục bài bản
- Áp dụng TLS bắt buộc, 2FA, và giám sát liên tục

