# Upstream Notes

This is a community wrapper around NetAlertX's experimental bare-metal deployment method.

Useful upstream references:

- https://docs.netalertx.com/HW_INSTALL/
- https://docs.netalertx.com/BACKUPS/
- https://docs.netalertx.com/MIGRATION/
- https://docs.netalertx.com/DOCKER_INSTALLATION/
- https://docs.netalertx.com/SETTINGS_SYSTEM/
- https://github.com/netalertx/NetAlertX/releases
- https://github.com/netalertx/NetAlertX/discussions/1570

The first working script was based on failures observed in Debian 13/Proxmox: the `api` symlink conflict, incomplete Proxmox requirements, missing runtime files, missing PHP-FPM variables, and missing nginx Python API routes. v3 keeps those fixes and adds version pinning plus lifecycle management.
