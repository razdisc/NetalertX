# Changelog

## v3.0.0 — Final first-generation controller

- Pin default NetAlertX release to `v26.9.0`.
- Move persistent config/database/runtime out of `/app`.
- Add `netalertxctl` for status/version/doctor/backup/update/rollback/reinstall/remove.
- Add staged updates and automatic rollback on validation failure.
- Keep nginx/systemd/controller files outside the replaceable source tree.
- Preserve all Debian 13/Proxmox fixes from v2.

## v2.0.0 — Working Debian 13 LXC deployment

- Fixed `/app/api` symlink conflict.
- Used root requirements for `pydantic` and `mcp`.
- Added `/data` compatibility paths.
- Added persistent runtime logs/API cache.
- Added PHP-FPM variables, API token, nginx API proxy and systemd.

## v1.0.0 — First working script

- Started from the upstream Debian/Proxmox installer and repaired the Debian 13 failures encountered in the homelab.
