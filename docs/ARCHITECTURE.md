# Architecture

```text
Browser
  |
  v
nginx :20211
  |--------------------------|
  |                          |
  v                          v
PHP frontend             Python API :20212
/app/front               /app/server
  |                          |
  +------------+-------------+
               v
       /var/lib/netalertx
        |       |       |
      config    db    runtime
```

## Paths

```text
/app/config -> /var/lib/netalertx/config
/app/db     -> /var/lib/netalertx/db
/app/api    -> /tmp/api -> /var/lib/netalertx/runtime/api
/app/log    -> /tmp/log -> /var/lib/netalertx/runtime/log

/data/config -> /var/lib/netalertx/config
/data/db     -> /var/lib/netalertx/db
/data/api    -> /tmp/api
/data/log    -> /tmp/log
```

## nginx

The crucial custom routing is:

```nginx
location /server/ { proxy_pass http://127.0.0.1:20212/; }
location /api/    { proxy_pass http://127.0.0.1:20212/; }
```

The trailing slash strips the frontend prefix before forwarding to Python. This fixes the failure where `/server/sse/state` was being handled by PHP and returned a `302 /devices.php`.

## systemd

The backend runs as `www-data`. `ExecStartPre` recreates volatile `/tmp` links and runtime files on every service start, then the launcher executes the Python server with `PYTHONPATH=/app`.

## Discovery permissions

Only `/usr/sbin/arp-scan` is granted through `/etc/sudoers.d/netalertx-arpscan`.
