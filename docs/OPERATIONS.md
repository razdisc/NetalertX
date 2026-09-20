# Operations

## Status / version / health

```bash
netalertxctl status
netalertxctl version
netalertxctl doctor
```

## Logs

```bash
journalctl -u netalertx -n 100 --no-pager
journalctl -u netalertx -f
```

Persistent logs:

```text
/var/lib/netalertx/runtime/log/
```

Important files include `app.log`, `execution_queue.log`, `app_front.log`, `app.php_errors.log`, `stderr.log`, `stdout.log`, `db_is_locked.log`.

## Backup

```bash
netalertxctl backup
```

## Restart

```bash
systemctl restart netalertx
netalertxctl doctor
```

## Update

```bash
netalertxctl update v26.9.0
```

## Rollback

```bash
find /var/backups/netalertx -mindepth 1 -maxdepth 1 -type d -print | sort
netalertxctl rollback /var/backups/netalertx/<backup>
```

## Remove

Normal removal keeps persistent state:

```bash
netalertxctl remove
```

Full purge:

```bash
netalertxctl remove --purge
```
