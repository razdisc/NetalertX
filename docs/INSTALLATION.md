# Installation

## Prerequisites

Create a fresh Debian 13 (Trixie) Proxmox LXC. The original deployment used a small LXC with `nesting=1`; size CPU/RAM/disk according to scan load.

## Install

```bash
apt-get update
apt-get install -y git
```

Copy this repository into the LXC and run:

```bash
chmod +x scripts/install-netalertx.sh
./scripts/install-netalertx.sh
```

The default target is `v26.9.0`.

## What the installer changes

- updates Debian packages;
- installs nginx, PHP 8.4/FPM, Python and discovery tools;
- clones a pinned NetAlertX release;
- creates `/app` runtime symlinks;
- stores config/DB/runtime outside `/app`;
- installs the full root `requirements.txt`;
- creates an API token;
- configures PHP-FPM variables;
- configures nginx Python API proxy routes;
- creates the `netalertx` systemd unit;
- installs `netalertxctl`;
- runs API, GraphQL, nginx and permission checks.

## First checks

```bash
netalertxctl status
netalertxctl doctor
```

Open:

```text
http://<LXC-IP>:20211
```
