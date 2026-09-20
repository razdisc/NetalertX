#!/usr/bin/env bash
set -Eeuo pipefail

# NetAlertX Debian 13 / Proxmox LXC installer - v3.0.0
# Fresh-install script. Lifecycle operations are provided by netalertxctl.

REPO="https://github.com/netalertx/NetAlertX.git"
NETALERTX_REF="${NETALERTX_REF:-v26.9.0}"
PORT="${PORT:-20211}"
GRAPHQL_PORT="${GRAPHQL_PORT:-20212}"
APP_DIR=/app
STATE_DIR=/var/lib/netalertx
CONFIG_DIR="$STATE_DIR/config"
DB_DIR="$STATE_DIR/db"
RUNTIME_DIR="$STATE_DIR/runtime"
RUNTIME_API="$RUNTIME_DIR/api"
RUNTIME_LOG="$RUNTIME_DIR/log"
BACKUP_ROOT=/var/backups/netalertx
ETC_DIR=/etc/netalertx
VENV_DIR=/opt/netalertx/venv
WEB_UI=/var/www/html/netalertx
NGINX_CONF="$ETC_DIR/netalertx.conf"
NGINX_LINK=/etc/nginx/conf.d/netalertx.conf
SYSTEMD_UNIT=/etc/systemd/system/netalertx.service
START_SCRIPT=/usr/local/lib/netalertx/start.sh
API_TOKEN_FILE="$ETC_DIR/api-token"
CTL_PATH=/usr/local/bin/netalertxctl

log(){ printf '\n[NETALERTX] %s\n' "$*"; }
fail(){ printf '\n[ERROR] %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || fail "Run as root."
source /etc/os-release
[[ "${ID:-}" == debian && "${VERSION_ID:-}" == 13 ]] || fail "Debian 13 (Trixie) required; detected ${ID:-unknown} ${VERSION_ID:-unknown}."

if [[ "${NETALERTX_ASSUME_YES:-0}" != 1 ]]; then
  cat <<WARN
============================================================
NetAlertX Debian 13 / Proxmox LXC installer v3.0.0
Target: ${NETALERTX_REF}

FRESH INSTALL ONLY.
This replaces /app and installs nginx/PHP/Python dependencies.
Persistent data is kept outside /app under /var/lib/netalertx.
Future lifecycle operations are handled by netalertxctl.
============================================================
WARN
  read -r -p "Type YES to continue: " answer
  [[ "${answer^^}" == YES ]] || exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y --no-install-recommends \
  ca-certificates curl openssl git sudo nginx tini snmp libwww-perl arp-scan perl apt-utils cron \
  php8.4 php8.4-cli php8.4-cgi php8.4-fpm php8.4-sqlite3 php8.4-curl sqlite3 dnsutils net-tools mtr \
  python3 python3-dev python3-psutil iproute2 nmap fping python3-pip python3-venv zip usbutils traceroute \
  nbtscan avahi-daemon avahi-utils build-essential gnupg2 lsb-release debian-archive-keyring

mkdir -p "$STATE_DIR" "$CONFIG_DIR" "$DB_DIR" "$RUNTIME_API" "$RUNTIME_LOG/plugins" \
  "$BACKUP_ROOT" "$ETC_DIR" "$(dirname "$START_SCRIPT")"

systemctl stop netalertx.service 2>/dev/null || true
pkill -f '^python(3)? .*\/app\/server/?$' 2>/dev/null || true

# Do not destroy a pre-existing default nginx site without keeping a backup.
if [[ -L /etc/nginx/sites-enabled/default ]]; then
  rm -f /etc/nginx/sites-enabled/default
elif [[ -f /etc/nginx/sites-enabled/default ]]; then
  mv /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default.bkp_netalertx
fi

TMP="$(mktemp -d /var/tmp/netalertx.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
log "Cloning NetAlertX ${NETALERTX_REF}"
git clone --depth 1 --branch "$NETALERTX_REF" "$REPO" "$TMP/app"
[[ -d "$TMP/app/server" && -d "$TMP/app/front" ]] || fail "Target release missing server/front."
[[ -f "$TMP/app/requirements.txt" ]] || fail "Target release missing requirements.txt."
[[ -f "$TMP/app/back/app.conf" && -f "$TMP/app/back/app.db" ]] || fail "Target release missing starter config/database."
COMMIT="$(git -C "$TMP/app" rev-parse HEAD)"
TAG="$(git -C "$TMP/app" describe --tags --exact-match 2>/dev/null || true)"
rm -rf "$APP_DIR"
mv "$TMP/app" "$APP_DIR"

# Persistent state is outside /app so updates can replace the source tree safely.
rm -rf "$APP_DIR/config" "$APP_DIR/db"
ln -s "$CONFIG_DIR" "$APP_DIR/config"
ln -s "$DB_DIR" "$APP_DIR/db"
rm -f "$APP_DIR/api" "$APP_DIR/log"
ln -s /tmp/api "$APP_DIR/api"
ln -s /tmp/log "$APP_DIR/log"

[[ -f "$APP_DIR/front/buildtimestamp.txt" ]] || date +%s > "$APP_DIR/front/buildtimestamp.txt"
[[ -f "$CONFIG_DIR/app.conf" ]] || cp "$APP_DIR/back/app.conf" "$CONFIG_DIR/app.conf"
[[ -f "$DB_DIR/app.db" ]] || cp "$APP_DIR/back/app.db" "$DB_DIR/app.db"

set_conf(){
  python3 - "$1" "$2" "$3" <<'PY'
import sys
key,val,path=sys.argv[1:]
lines=open(path,encoding='utf-8').read().splitlines()
out=[]; done=False
for line in lines:
    if line.startswith(key+'='):
        if not done: out.append(f'{key}={val}'); done=True
    else: out.append(line)
if not done: out.append(f'{key}={val}')
open(path,'w',encoding='utf-8').write('\n'.join(out)+'\n')
PY
}
set_conf BACKEND_API_URL "'/server'" "$CONFIG_DIR/app.conf"
set_conf GRAPHQL_PORT "$GRAPHQL_PORT" "$CONFIG_DIR/app.conf"

if grep -q '^API_TOKEN=' "$CONFIG_DIR/app.conf"; then
  API_TOKEN="$(python3 - "$CONFIG_DIR/app.conf" <<'PY'
import ast,re,sys
s=open(sys.argv[1],encoding='utf-8').read(); m=re.search(r'^API_TOKEN=(.*)$',s,re.M)
print(ast.literal_eval(m.group(1)) if m else '')
PY
)"
else
  API_TOKEN="t_$(openssl rand -hex 24)"
  printf "API_TOKEN='%s'\n" "$API_TOKEN" >> "$CONFIG_DIR/app.conf"
fi
printf '%s\n' "$API_TOKEN" > "$API_TOKEN_FILE"
chmod 600 "$API_TOKEN_FILE"

# Runtime state mirrors the application's expected /tmp paths but survives reboot.
mkdir -p "$RUNTIME_API" "$RUNTIME_LOG/plugins"
touch "$RUNTIME_LOG"/{app.log,execution_queue.log,app_front.log,app.php_errors.log,stderr.log,stdout.log,db_is_locked.log}
touch "$RUNTIME_API/user_notifications.json"
ln -sfn "$RUNTIME_API" /tmp/api
ln -sfn "$RUNTIME_LOG" /tmp/log
mkdir -p /data
ln -sfn "$CONFIG_DIR" /data/config
ln -sfn "$DB_DIR" /data/db
ln -sfn /tmp/api /data/api
ln -sfn /tmp/log /data/log

log "Building Python environment"
rm -rf "${VENV_DIR}.new" "$VENV_DIR"
python3 -m venv "${VENV_DIR}.new"
"${VENV_DIR}.new/bin/python" -m pip install --upgrade pip wheel setuptools
"${VENV_DIR}.new/bin/python" -m pip install -r "$APP_DIR/requirements.txt"
mv "${VENV_DIR}.new" "$VENV_DIR"

chown -R www-data:www-data "$CONFIG_DIR" "$DB_DIR" "$RUNTIME_DIR"
chgrp -R www-data "$APP_DIR"
chmod -R ug+rwX,o-rwx "$CONFIG_DIR" "$DB_DIR" "$RUNTIME_DIR"
chmod 664 "$CONFIG_DIR/app.conf" "$DB_DIR/app.db"

cat > /etc/sudoers.d/netalertx-arpscan <<'EOF_SUDO'
www-data ALL=(root) NOPASSWD: /usr/sbin/arp-scan
EOF_SUDO
chmod 440 /etc/sudoers.d/netalertx-arpscan
visudo -c -f /etc/sudoers.d/netalertx-arpscan >/dev/null

PHP_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
PHP_POOL="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
PHP_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"
[[ -f "$PHP_POOL" ]] || fail "PHP-FPM pool not found: $PHP_POOL"
set_php_env(){
  local key="$1" val="$2"
  if grep -q "^env\[${key}\]" "$PHP_POOL"; then
    sed -i "s|^env\[${key}\].*|env[${key}] = ${val}|" "$PHP_POOL"
  else
    printf 'env[%s] = %s\n' "$key" "$val" >> "$PHP_POOL"
  fi
}
set_php_env NETALERTX_APP "$APP_DIR"
set_php_env NETALERTX_DATA /data
set_php_env NETALERTX_TMP "$APP_DIR"
set_php_env NETALERTX_CONFIG "$CONFIG_DIR"
set_php_env NETALERTX_DB "$DB_DIR"
set_php_env NETALERTX_LOG "$APP_DIR/log"
set_php_env NETALERTX_API "$APP_DIR/api"

mkdir -p /var/www/html "$ETC_DIR"
ln -sfn "$APP_DIR/front" "$WEB_UI"
cat > "$NGINX_CONF" <<EOF_NGINX
server {
  listen ${PORT};
  server_name _;
  root ${WEB_UI};
  index index.php;
  add_header X-Forwarded-Prefix "/netalertx" always;
  proxy_set_header X-Forwarded-Prefix "/netalertx";
  charset utf-8;

  location /server/ {
    proxy_pass http://127.0.0.1:${GRAPHQL_PORT}/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header Authorization \$http_authorization;
    proxy_read_timeout 3600;
    proxy_send_timeout 3600;
    proxy_buffering off;
    proxy_cache off;
  }

  location /api/ {
    proxy_pass http://127.0.0.1:${GRAPHQL_PORT}/;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header Authorization \$http_authorization;
    proxy_read_timeout 3600;
    proxy_send_timeout 3600;
    proxy_buffering off;
    proxy_cache off;
  }

  location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
  }

  location ~ \.php\$ {
    fastcgi_pass unix:${PHP_SOCK};
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    fastcgi_param PATH_INFO \$fastcgi_path_info;
    fastcgi_param QUERY_STRING \$query_string;
    include fastcgi_params;
  }
}
EOF_NGINX
ln -sfn "$NGINX_CONF" "$NGINX_LINK"

cat > "$START_SCRIPT" <<EOF_START
#!/usr/bin/env bash
set -Eeuo pipefail
export PYTHONPATH=/app
export PYTHONUNBUFFERED=1
cd /app
exec ${VENV_DIR}/bin/python /app/server/
EOF_START
chmod 755 "$START_SCRIPT"

cat > "$SYSTEMD_UNIT" <<'EOF_SERVICE'
[Unit]
Description=NetAlertX
After=network-online.target php8.4-fpm.service nginx.service
Wants=network-online.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/app
ExecStartPre=/bin/bash -c 'mkdir -p /var/lib/netalertx/runtime/api /var/lib/netalertx/runtime/log/plugins; ln -sfn /var/lib/netalertx/runtime/api /tmp/api; ln -sfn /var/lib/netalertx/runtime/log /tmp/log; ln -sfn /var/lib/netalertx/config /data/config; ln -sfn /var/lib/netalertx/db /data/db; ln -sfn /tmp/api /data/api; ln -sfn /tmp/log /data/log; rm -f /app/api /app/log /app/config /app/db; ln -s /tmp/api /app/api; ln -s /tmp/log /app/log; ln -s /var/lib/netalertx/config /app/config; ln -s /var/lib/netalertx/db /app/db; touch /var/lib/netalertx/runtime/log/app.log /var/lib/netalertx/runtime/log/execution_queue.log /var/lib/netalertx/runtime/log/app_front.log /var/lib/netalertx/runtime/log/app.php_errors.log /var/lib/netalertx/runtime/log/stderr.log /var/lib/netalertx/runtime/log/stdout.log /var/lib/netalertx/runtime/log/db_is_locked.log /var/lib/netalertx/runtime/api/user_notifications.json; chown -R www-data:www-data /var/lib/netalertx/config /var/lib/netalertx/db /var/lib/netalertx/runtime'
ExecStartPre=/bin/bash -c 'test -w /data/config/app.conf && test -w /data/db/app.db'
ExecStart=/usr/local/lib/netalertx/start.sh
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF_SERVICE

cat > "$ETC_DIR/netalertx.env" <<EOF_STATE
NETALERTX_REF='${NETALERTX_REF}'
NETALERTX_COMMIT='${COMMIT}'
NETALERTX_TAG='${TAG}'
INSTALLER_VERSION='3.0.0'
PORT='${PORT}'
GRAPHQL_PORT='${GRAPHQL_PORT}'
EOF_STATE
chmod 640 "$ETC_DIR/netalertx.env"

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
[[ -f "$SCRIPT_DIR/netalertxctl" ]] || fail "netalertxctl must be next to the installer."
install -m 0755 "$SCRIPT_DIR/netalertxctl" "$CTL_PATH"

systemctl daemon-reload
systemctl enable "php${PHP_VERSION}-fpm" nginx netalertx.service
systemctl restart "php${PHP_VERSION}-fpm"
nginx -t
systemctl restart nginx
systemctl restart netalertx.service

for _ in {1..30}; do
  curl -fsS -o /dev/null "http://127.0.0.1:${GRAPHQL_PORT}/docs" && break
  sleep 1
done
curl -fsS -o /dev/null "http://127.0.0.1:${GRAPHQL_PORT}/docs" || fail "Python backend did not start."

systemctl is-active --quiet netalertx || fail "netalertx service inactive"
nginx -t >/dev/null || fail "nginx configuration invalid"
code="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/server/sse/state")"
[[ "$code" == 401 ]] || fail "Expected /server/sse/state HTTP 401, got ${code}"
gql="$(curl -sS -o /tmp/netalertx-gql.json -w '%{http_code}' -X POST "http://127.0.0.1:${GRAPHQL_PORT}/graphql" -H "Authorization: Bearer ${API_TOKEN}" -H 'Content-Type: application/json' --data '{"query":"{ __typename }"}')"
[[ "$gql" == 200 ]] || fail "GraphQL validation failed: HTTP ${gql}"
grep -q '"__typename"' /tmp/netalertx-gql.json || fail "Unexpected GraphQL response"
sudo -u www-data test -w "$CONFIG_DIR/app.conf" || fail "app.conf not writable by www-data"
sudo -u www-data test -w "$DB_DIR/app.db" || fail "app.db not writable by www-data"

IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}')"
IP="${IP:-$(hostname -I | awk '{print $1}')}"
cat <<DONE
============================================================
NetAlertX v3.0.0 installed
Release: ${NETALERTX_REF}
Commit:  ${COMMIT}
Web UI:  http://${IP}:${PORT}

Persistent state: ${STATE_DIR}
API token: ${API_TOKEN_FILE}
Controller: ${CTL_PATH}

Try:
  netalertxctl status
  netalertxctl doctor
============================================================
DONE
