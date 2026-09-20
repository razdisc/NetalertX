# Upgrading

NetAlertX has documented breaking changes and database migration requirements. v3 therefore does not use `git pull` or silently track `main`.

## Normal update

```bash
netalertxctl update <tested-release>
```

The controller:

1. backs up config, DB, source and Python venv;
2. clones the target release into a staging directory;
3. builds a new Python venv from that release;
4. switches `/app` and the venv;
5. preserves `/var/lib/netalertx/config` and `/var/lib/netalertx/db`;
6. recreates runtime links;
7. starts the service;
8. validates nginx, Python API, GraphQL and write permissions;
9. deletes the old copy only after success.

If validation fails, the previous source, venv, config and DB are restored.

## Important

For large jumps, read the upstream migration guide first. The upstream documentation states that some old releases require intermediate versions because database structures change.
