#!/usr/bin/env bash
# Bài 5 - Quản lý quyền sở hữu thư mục Web
# Cách chạy: sudo bash setup_permissions.sh
set -e

WEB_DIR=/var/www/ptit-web

# 1. Đổi owner -> devops, group -> www-data (đệ quy cho toàn bộ nội dung)
chown -R devops:www-data "$WEB_DIR"

# 2. Phân quyền
#    Thư mục: 2750 = rwxr-s---
#      - bit x là BẮT BUỘC để Nginx (www-data) đi vào thư mục, thiếu x -> 403 Forbidden
#      - bit setgid (2) để file/thư mục mới tạo tự thừa hưởng group www-data
#    File   : 640 = rw-r-----
#      - devops đọc/ghi, www-data chỉ đọc, others không có quyền
find "$WEB_DIR" -type d -exec chmod 2750 {} \;
find "$WEB_DIR" -type f -exec chmod 640 {} \;

ls -la "$WEB_DIR" "$WEB_DIR/html"
