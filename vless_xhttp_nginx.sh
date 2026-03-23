#!/usr/bin/env bash

set -euxo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/vless_common.sh"

DOMAIN="${DOMAIN:-x.example.com}"
EMAIL="${EMAIL:-example@example.com}"
XRAY_CONFIG_PATH="${XRAY_CONFIG_PATH:-/usr/local/etc/xray/config.json}"
XRAY_LOGLEVEL="${XRAY_LOGLEVEL:-warning}"
XRAY_ACCESS_LOG="${XRAY_ACCESS_LOG:-/var/log/xray/access.log}"
XRAY_ERROR_LOG="${XRAY_ERROR_LOG:-/var/log/xray/error.log}"
XRAY_LISTEN="${XRAY_LISTEN:-/dev/shm/xray-xhttp.sock,0666}"
CLIENT_FLOW="${CLIENT_FLOW:-}"
XHTTP_PATH="${XHTTP_PATH:-/database}"
XHTTP_MODE="${XHTTP_MODE:-stream-one}"
TLS_SERVER_PORT="${TLS_SERVER_PORT:-443}"
HTTP_SERVER_PORT="${HTTP_SERVER_PORT:-80}"
QR_TYPE="${QR_TYPE:-ANSIUTF8}"
CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-chrome}"
PROFILE_NAME="${PROFILE_NAME:-XHTTP}"
NGINX_CONF_PATH="${NGINX_CONF_PATH:-/etc/nginx/conf.d/xray.conf}"
CERTBOT_CERT_PATH="${CERTBOT_CERT_PATH:-/etc/letsencrypt/live/$DOMAIN/fullchain.pem}"
CERTBOT_KEY_PATH="${CERTBOT_KEY_PATH:-/etc/letsencrypt/live/$DOMAIN/privkey.pem}"
CERTBOT_OPTIONS_PATH="${CERTBOT_OPTIONS_PATH:-/etc/letsencrypt/options-ssl-nginx.conf}"
CERTBOT_DHPARAM_PATH="${CERTBOT_DHPARAM_PATH:-/etc/letsencrypt/ssl-dhparams.pem}"

usage() {
	cat <<'EOF'
Usage:
  ./vless_xhttp_nginx.sh

Environment overrides:
  UUID                 Client UUID for Xray.
  DOMAIN               Public hostname for nginx and the generated vless:// link.
  EMAIL                Email for certbot registration.
  XRAY_CONFIG_PATH     Xray config path.
  XRAY_LOGLEVEL        Xray log level.
  XRAY_ACCESS_LOG      Xray access log path.
  XRAY_ERROR_LOG       Xray error log path.
  XRAY_LISTEN          Xray unix socket with mode.
  CLIENT_FLOW          VLESS flow value.
  XHTTP_PATH           XHTTP path.
  XHTTP_MODE           XHTTP mode.
  TLS_SERVER_PORT      Public TLS/QUIC port.
  HTTP_SERVER_PORT     Public HTTP port.
  QR_TYPE              qrencode output type.
  CLIENT_FINGERPRINT   Client fingerprint in the generated vless:// link.
  PROFILE_NAME         Link label prefix after #.
  NGINX_CONF_PATH      Nginx config path.
  CERTBOT_CERT_PATH    TLS certificate path for nginx.
  CERTBOT_KEY_PATH     TLS private key path for nginx.
  CERTBOT_OPTIONS_PATH Included Certbot nginx options path.
  CERTBOT_DHPARAM_PATH DH params path.
EOF
}

maybe_print_help "${1:-}" usage
UUID="${UUID:-$(generate_uuid)}"
NGINX_LOCATION_PATH="${XHTTP_PATH%/}/"

apt update
apt upgrade -y
apt autoremove -y --purge
apt install -y curl openssl qrencode gnupg2 ca-certificates lsb-release ubuntu-keyring

curl https://nginx.org/keys/nginx_signing.key |
	gpg --dearmor |
	tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
https://nginx.org/packages/mainline/ubuntu $(lsb_release -cs) nginx" |
	tee /etc/apt/sources.list.d/nginx.list

cat >/etc/apt/preferences.d/99nginx <<EOF
Package: *
Pin: origin nginx.org
Pin: release o=nginx
Pin-Priority: 900
EOF

systemctl stop nginx || true
apt remove -y nginx nginx-common nginx-full nginx-core certbot python3-certbot-nginx || true
apt update
apt upgrade -y
apt autoremove -y --purge
apt install -y nginx certbot python3-certbot-nginx

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
xray version

cat >"$XRAY_CONFIG_PATH" <<EOF
{
    "log": {
        "loglevel": "$XRAY_LOGLEVEL",
        "access": "$XRAY_ACCESS_LOG",
        "error": "$XRAY_ERROR_LOG"
    },
    "inbounds": [
        {
            "listen": "$XRAY_LISTEN",
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "flow": "$CLIENT_FLOW"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "xhttp",
                "security": "none",
                "xhttpSettings": {
                    "path": "$XHTTP_PATH",
                    "mode": "$XHTTP_MODE"
                }
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom"
        }
    ]
}
EOF

systemctl enable xray
systemctl restart xray
systemctl status xray --no-pager

cat >"$NGINX_CONF_PATH" <<EOF
server {
    listen $HTTP_SERVER_PORT;
    listen [::]:$HTTP_SERVER_PORT;

    server_name $DOMAIN;

    location / {
        return 200 'ok';
        add_header Content-Type text/plain;
    }
}
EOF

nginx -t
systemctl reload nginx

certbot --nginx -d "$DOMAIN" \
	--non-interactive \
	--agree-tos \
	--email "$EMAIL" \
	--no-eff-email

cat >"$NGINX_CONF_PATH" <<EOF
server {
    listen $TLS_SERVER_PORT      ssl http2;
    listen [::]:$TLS_SERVER_PORT ssl http2;
    listen $TLS_SERVER_PORT      quic reuseport;
    listen [::]:$TLS_SERVER_PORT quic reuseport;

    add_header Alt-Svc 'h3=":$TLS_SERVER_PORT"; ma=86400' always;

    server_name $DOMAIN;

    location / {
        return 200 'ok';
        add_header Content-Type text/plain;
    }

    location ^~ $NGINX_LOCATION_PATH {
        client_max_body_size 0;

        grpc_read_timeout 300s;
        grpc_send_timeout 300s;

        grpc_set_header X-Real-IP       \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        grpc_pass grpc://unix:${XRAY_LISTEN%%,*};
    }

    ssl_certificate     $CERTBOT_CERT_PATH;
    ssl_certificate_key $CERTBOT_KEY_PATH;

    include     $CERTBOT_OPTIONS_PATH;
    ssl_dhparam $CERTBOT_DHPARAM_PATH;
}

server {
    if (\$host = $DOMAIN) {
        return 301 https://\$host\$request_uri;
    }

    listen $HTTP_SERVER_PORT;
    listen [::]:$HTTP_SERVER_PORT;

    server_name $DOMAIN;

    return 404;
}
EOF

nginx -t
systemctl reload nginx

curl -I http://127.0.0.1
curl -Ik https://"$DOMAIN"

journalctl -u xray -n 100 --no-pager
tail -n 100 /var/log/nginx/error.log
tail -n 100 /var/log/xray/error.log

URL_PATH="$(url_encode "$XHTTP_PATH")"
URL="vless://$UUID@$DOMAIN:$TLS_SERVER_PORT?security=tls&sni=$DOMAIN&alpn=h3&type=xhttp&path=$URL_PATH&mode=$XHTTP_MODE&encryption=none&fp=$CLIENT_FINGERPRINT#$PROFILE_NAME-$DOMAIN-$UUID"

print_qr_and_url "$QR_TYPE" "$URL"
