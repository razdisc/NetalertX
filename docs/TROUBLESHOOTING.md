# Troubleshooting

## `/app/api` already exists

The repo tracks `api` as a runtime symlink. v3 deliberately recreates `/app/api -> /tmp/api` after checkout.

## `pydantic` missing

Use the repository root `requirements.txt`, not the old Proxmox-specific requirements. v3 does this by default.

## `/data/config/app.conf` missing

Check:

```bash
ls -l /data/config/app.conf /app/config/app.conf
```

Expected both to resolve into `/var/lib/netalertx/config`.

## UI works but Settings/Plugins fail

Test:

```bash
curl -i http://127.0.0.1:20211/server/sse/state
```

Expected unauthenticated result:

```text
HTTP/1.1 401
```

A `302` to `/devices.php` means nginx is routing `/server/*` to PHP. Check `/etc/netalertx/netalertx.conf` and run `nginx -t`.

## `app.conf` not writable

```bash
sudo -u www-data test -w /var/lib/netalertx/config/app.conf && echo OK
sudo -u www-data test -w /var/lib/netalertx/db/app.db && echo OK
```

## GraphQL unauthorized

```bash
TOKEN=$(cat /etc/netalertx/api-token)
curl -sS -X POST http://127.0.0.1:20212/graphql \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{"query":"{ __typename }"}'
```

Expected JSON contains `"__typename":"Query"`.

## Service failure

```bash
systemctl status netalertx --no-pager
journalctl -u netalertx -n 100 --no-pager
netalertxctl doctor
```
