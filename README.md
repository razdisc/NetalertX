# NetAlertX Debian 13 Proxmox LXC — v3

Finalized first-generation homelab deployment for running NetAlertX directly inside a Debian 13 (Trixie) Proxmox LXC.

> NetAlertX currently labels bare-metal installation experimental and recommends Docker as the supported deployment method. This repository is a homelab-specific wrapper around the experimental method.

## Why v3

The first working scripts repaired the Debian 13/Proxmox failures we hit:

- `/app/api` symlink conflict
- incomplete Proxmox Python requirements (`pydantic` / `mcp`)
- `/data` and `/tmp` runtime paths
- missing runtime log files
- PHP-FPM `NETALERTX_*` variables
- GraphQL API token
- nginx `/server/` and `/api/` proxying
- `PYTHONPATH=/app`
- `www-data` permission to run `arp-scan`

v3 keeps those fixes and adds lifecycle management.

## Main improvement

Application code is replaceable:

```text
/app                         application source
/var/lib/netalertx/config    persistent configuration
/var/lib/netalertx/db        persistent database
/var/lib/netalertx/runtime   persistent API/log runtime data
```

So an update does not require destroying the database or configuration.

## Controller

```bash
netalertxctl status
netalertxctl version
netalertxctl doctor
netalertxctl backup
netalertxctl update v26.9.0
netalertxctl rollback /var/backups/netalertx/<backup>
netalertxctl reinstall v26.9.0
netalertxctl remove
netalertxctl remove --purge
```

Updates are staged and validated. A failed update restores the previous source tree, Python environment, config and database.

## Pinned upstream release

Default: **v26.9.0** (`a686a01` on the current GitHub release page). v26.9.0 is significant because the release notes call out a breaking plugin-directory move from `/front/plugins` to `/server/plugins` and the switch to CalVer. For that reason this project pins releases instead of following `main`.

## Install

The recommended workflow is to prepare the fresh Debian 13 LXC, update Debian, clone this repository, and then run the installer.

### 1. Update Debian

Run these commands inside the fresh LXC:

```bash
apt update
apt full-upgrade -y
apt install -y git ca-certificates
```

Reboot if Debian/kernel updates request it:

```bash
reboot
```

After reconnecting, confirm the OS:

```bash
cat /etc/os-release
```

This project targets **Debian 13 (Trixie)**.

### 2. Clone this repository

Replace `<YOUR_GITHUB_USERNAME>/<YOUR_REPOSITORY>` with the GitHub repository that contains this project:

```bash
cd /root

# SSH (recommended)
git clone git@github.com:razdisc/NetalertX.git

# OR HTTPS with a GitHub Personal Access Token
git clone https://github.com/razdisc/NetalertX.git

cd /root/netalertx-debian13-lxc
```

Verify that the expected files are present:

```bash
ls -la
ls -la scripts/
```

### 3. Run the installer

```bash
chmod +x scripts/install-netalertx.sh
sudo ./scripts/install-netalertx.sh
```

The installer performs the remaining OS package installation and configures NetAlertX, nginx, PHP-FPM, Python, systemd, persistent storage and `netalertxctl`.

For unattended installation:

```bash
sudo NETALERTX_ASSUME_YES=1 ./scripts/install-netalertx.sh
```

### 4. Verify the installation

```bash
netalertxctl status
netalertxctl doctor
netalertxctl version
```

Open:

```text
http://<LXC-IP>:20211
```

## Verify

```bash
netalertxctl doctor
curl -i http://127.0.0.1:20211/server/sse/state
```

Without an Authorization header, `/server/sse/state` should return **401**. A **302 to `/devices.php` means nginx is incorrectly routing the Python API request into PHP**.

## Persistent mappings

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

## Backups and migrations

Before updates, v3 creates `/var/backups/netalertx/<timestamp>-<reason>/` containing config, DB, exact `/app`, Python venv and state metadata.

NetAlertX's current backup documentation recommends preserving configuration and database data and warns that DB structures can change between releases. Follow the upstream migration guide for large or old-version jumps instead of blindly updating.

## Upstream references

- https://docs.netalertx.com/HW_INSTALL/
- https://docs.netalertx.com/BACKUPS/
- https://docs.netalertx.com/MIGRATION/
- https://docs.netalertx.com/DOCKER_INSTALLATION/
- https://github.com/netalertx/NetAlertX/releases
- https://github.com/netalertx/NetAlertX/discussions/1570
