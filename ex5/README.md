# Bài 5: Quản lý quyền sở hữu thư mục Web (Directory Permission Management)

## 1. Mục tiêu

- Hiểu cơ chế phân quyền `chown` / `chmod` trên Linux.
- Cho phép user **devops** sửa mã nguồn web trong `/var/www/ptit-web/` **không cần sudo**.
- Nginx (worker chạy dưới user **www-data**) vẫn đọc được file, **không bị lỗi 403 Forbidden**.

## 2. Môi trường thực hành

| Thành phần | Giá trị |
|---|---|
| OS | Ubuntu 24.04 LTS |
| Web server | nginx/1.24.0 (Ubuntu) |
| Thư mục web | `/var/www/ptit-web/html` (document root của Nginx) |
| User triển khai | `devops` |
| User chạy Nginx | `www-data` |

Xác nhận worker của Nginx chạy dưới user `www-data`:

```
$ ps -o user,cmd -C nginx
USER     CMD
root     nginx: master process nginx
www-data nginx: worker process
www-data nginx: worker process
...
```

## 3. Hiện trạng ban đầu (thư mục thuộc root)

```
$ ls -la /var/www/ptit-web/
total 12
drwxr-xr-x 3 root root 4096 Sep 30 14:15 .
drwxr-xr-x 4 root root 4096 Sep 30 14:15 ..
drwxr-xr-x 2 root root 4096 Sep 30 14:15 html

$ ls -la /var/www/ptit-web/html/
total 12
drwxr-xr-x 2 root root 4096 Sep 30 14:15 .
drwxr-xr-x 3 root root 4096 Sep 30 14:15 ..
-rw-r--r-- 1 root root   21 Sep 30 14:15 index.html
```

User `devops` **không thể** ghi file:

```
devops$ echo "Update" >> /var/www/ptit-web/html/index.html
-bash: line 1: /var/www/ptit-web/html/index.html: Permission denied
```

## 4. Các bước thực hiện

### Bước 1 – Đổi chủ sở hữu và nhóm sở hữu (đệ quy)

```bash
sudo chown -R devops:www-data /var/www/ptit-web
```

- Owner → `devops` (người deploy, được sửa file).
- Group → `www-data` (nhóm của Nginx, được đọc file).

### Bước 2 – Phân quyền cho thư mục và file

```bash
# Thư mục: rwxr-s---  (2750)
sudo find /var/www/ptit-web -type d -exec chmod 2750 {} \;

# File:    rw-r-----  (640)
sudo find /var/www/ptit-web -type f -exec chmod 640 {} \;
```

| Đối tượng | Quyền | Owner (devops) | Group (www-data) | Others |
|---|---|---|---|---|
| Thư mục | `2750` = `rwxr-s---` | đọc, ghi, truy cập | đọc, truy cập | không có quyền |
| File | `640` = `rw-r-----` | đọc, ghi | chỉ đọc | không có quyền |

**Vì sao không dùng `chmod -R 640` cho tất cả?**
Với thư mục, bit **`x` (execute)** là quyền "đi vào" (traverse) thư mục. Nếu thư mục chỉ có `r` mà không có `x`, Nginx
không mở được file bên trong → **403 Forbidden** (log: `Permission denied`). Vì vậy thư mục cần `x`, còn file tĩnh
(HTML/CSS/JS/ảnh) thì không cần `x`. Dùng `find -type d` / `find -type f` để tách riêng hai loại.

**Bit setgid (`2` ở đầu `2750`, hiển thị là `s`)**: file/thư mục mới do `devops` tạo ra sau này sẽ tự động thuộc group
`www-data`, nên Nginx vẫn đọc được mà không phải `chown` lại mỗi lần deploy.

> Toàn bộ các lệnh trên được gom trong script [`setup_permissions.sh`](./setup_permissions.sh).

## 5. Kết quả kiểm tra

### 5.1. `ls -la /var/www/ptit-web/` sau khi phân quyền

```
$ ls -la /var/www/ptit-web/
total 12
drwxr-s--- 3 devops www-data 4096 Sep 30 14:15 .
drwxr-xr-x 4 root   root     4096 Sep 30 14:15 ..
drwxr-s--- 2 devops www-data 4096 Sep 30 14:15 html

$ ls -la /var/www/ptit-web/html/
total 12
drwxr-s--- 2 devops www-data 4096 Sep 30 14:15 .
drwxr-s--- 3 devops www-data 4096 Sep 30 14:15 ..
-rw-r----- 1 devops www-data   21 Sep 30 14:15 index.html

$ stat -c "%A %a %U:%G %n" /var/www/ptit-web /var/www/ptit-web/html /var/www/ptit-web/html/index.html
drwxr-s--- 2750 devops:www-data /var/www/ptit-web
drwxr-s--- 2750 devops:www-data /var/www/ptit-web/html
-rw-r----- 640 devops:www-data /var/www/ptit-web/html/index.html
```

### 5.2. Ghi file bằng user `devops` (không dùng sudo) → **thành công**

```
$ su - devops
devops$ whoami
devops
devops$ echo "Update" >> /var/www/ptit-web/html/index.html && echo "Ghi thanh cong"
Ghi thanh cong
devops$ cat /var/www/ptit-web/html/index.html
<h1>PTIT Web v1</h1>
Update
```

### 5.3. User khác (others) không truy cập được

```
$ su - guest -c "cat /var/www/ptit-web/html/index.html"
cat: /var/www/ptit-web/html/index.html: Permission denied
```

### 5.4. Nginx đọc được file, web hiển thị nội dung mới – **không lỗi 403**

```
$ sudo -u www-data cat /var/www/ptit-web/html/index.html
<h1>PTIT Web v1</h1>
Update

$ sudo nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful

$ curl -i http://localhost/
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Date: Wed, 30 Sep 2026 14:15:22 GMT
Content-Type: text/html
Content-Length: 28
Last-Modified: Wed, 30 Sep 2026 14:15:22 GMT
Connection: keep-alive
ETag: "6abd197a-1c"
Accept-Ranges: bytes

<h1>PTIT Web v1</h1>
Update

$ tail -n 5 /var/log/nginx/error.log
(trống – không có lỗi Permission denied / 403)
```

Log đầy đủ của toàn bộ quá trình: [`output.log`](./output.log).

## 6. Kết luận

| Yêu cầu | Kết quả |
|---|---|
| Owner của `/var/www/ptit-web/` và nội dung bên trong là `devops` | Đạt |
| Group sở hữu là `www-data` | Đạt |
| Owner đọc/ghi, group chỉ đọc, others không có quyền | Đạt (file `640`, thư mục `2750`) |
| `devops` ghi file không cần sudo | Đạt – `Ghi thanh cong` |
| Nginx phục vụ web bình thường, không 403 | Đạt – `HTTP/1.1 200 OK`, hiển thị nội dung mới |

**Lưu ý:** các thư mục cha (`/var`, `/var/www`) cũng phải có bit `x` cho www-data (mặc định là `755`), nếu không Nginx vẫn
bị 403 dù `/var/www/ptit-web` đã phân quyền đúng. Có thể kiểm tra nhanh bằng `namei -l /var/www/ptit-web/html/index.html`.
