#!/usr/bin/env bash

set -euxo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/vless_common.sh"

DOMAIN="${DOMAIN:-x.example.com}"
SNI="${SNI:-vk6-9.vkuser.net}"
XRAY_CONFIG_PATH="${XRAY_CONFIG_PATH:-/usr/local/etc/xray/config.json}"
XRAY_LOGLEVEL="${XRAY_LOGLEVEL:-warning}"
XRAY_ACCESS_LOG="${XRAY_ACCESS_LOG:-/var/log/xray/access.log}"
XRAY_ERROR_LOG="${XRAY_ERROR_LOG:-/var/log/xray/error.log}"
XRAY_PORT="${XRAY_PORT:-443}"
CLIENT_FLOW="${CLIENT_FLOW:-}"
XHTTP_PATH="${XHTTP_PATH:-/database}"
XHTTP_MODE="${XHTTP_MODE:-stream-one}"
REALITY_SHOW="${REALITY_SHOW:-false}"
REALITY_XVER="${REALITY_XVER:-0}"
REALITY_DEST_PORT="${REALITY_DEST_PORT:-443}"
SHORT_ID="${SHORT_ID:-}"
SNIFFING_ENABLED="${SNIFFING_ENABLED:-true}"
SNIFFING_DEST_OVERRIDE="${SNIFFING_DEST_OVERRIDE:-http,tls,quic}"
QR_TYPE="${QR_TYPE:-ANSIUTF8}"
CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-chrome}"
PROFILE_NAME="${PROFILE_NAME:-XHTTP}"

usage() {
	cat <<'EOF'
Usage:
  ./vless_xhttp_reality.sh

Environment overrides:
  UUID                   Client UUID for Xray.
  DOMAIN                 Public hostname for the generated vless:// link.
  SNI                    Reality destination server name.
  XRAY_CONFIG_PATH       Xray config path.
  XRAY_LOGLEVEL          Xray log level.
  XRAY_ACCESS_LOG        Xray access log path.
  XRAY_ERROR_LOG         Xray error log path.
  XRAY_PORT              Xray listen port.
  CLIENT_FLOW            VLESS flow value.
  XHTTP_PATH             XHTTP path.
  XHTTP_MODE             XHTTP mode.
  REALITY_SHOW           realitySettings.show.
  REALITY_XVER           realitySettings.xver.
  REALITY_DEST_PORT      Port in realitySettings.dest.
  SHORT_ID               Reality short ID. Default is random.
  SNIFFING_ENABLED       Sniffing enabled flag.
  SNIFFING_DEST_OVERRIDE Comma-separated sniffing overrides.
  QR_TYPE                qrencode output type.
  CLIENT_FINGERPRINT     Client fingerprint in the generated vless:// link.
  PROFILE_NAME           Link label prefix after #.
EOF
}

maybe_print_help "${1:-}" usage
UUID="${UUID:-$(generate_uuid)}"

apt update
apt upgrade -y
apt autoremove -y --purge
apt install -y curl openssl qrencode

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
xray version

OUT="$(xray x25519)"
PRIVATE_KEY="$(printf '%s\n' "$OUT" | awk -F': ' '/^PrivateKey:/ {print $2}')"
PUBLIC_KEY="$(printf '%s\n' "$OUT" | awk -F': ' '/^(Password|PublicKey):/ {print $2}')"
if [[ -z "$SHORT_ID" ]]; then
	SHORT_ID="$(openssl rand -hex 8)"
fi
URL_PATH="$(url_encode "$XHTTP_PATH")"
SNIFFING_DEST_OVERRIDE_JSON="$(python3 -c 'import json, os; print(json.dumps([item.strip() for item in os.environ["SNIFFING_DEST_OVERRIDE"].split(",") if item.strip()]))')"

cat >"$XRAY_CONFIG_PATH" <<EOF
{
    "log": {
        "loglevel": "$XRAY_LOGLEVEL",
        "access": "$XRAY_ACCESS_LOG",
        "error": "$XRAY_ERROR_LOG"
    },
    "inbounds": [
        {
            "port": $XRAY_PORT,
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
                "security": "reality",
                "realitySettings": {
                    "show": $REALITY_SHOW,
                    "dest": "$SNI:$REALITY_DEST_PORT",
                    "xver": $REALITY_XVER,
                    "serverNames": [
                        "$SNI"
                    ],
                    "privateKey": "$PRIVATE_KEY",
                    "shortIds": [
                        "$SHORT_ID"
                    ]
                },
                "xhttpSettings": {
                    "path": "$XHTTP_PATH",
                    "mode": "$XHTTP_MODE"
                }
            },
            "sniffing": {
                "enabled": $SNIFFING_ENABLED,
                "destOverride": $SNIFFING_DEST_OVERRIDE_JSON
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

journalctl -u xray -n 100 --no-pager
tail -n 100 /var/log/xray/error.log

URL="vless://$UUID@$DOMAIN:$XRAY_PORT?security=reality&sni=$SNI&alpn=h3&type=xhttp&path=$URL_PATH&mode=$XHTTP_MODE&encryption=none&pbk=$PUBLIC_KEY&sid=$SHORT_ID&fp=$CLIENT_FINGERPRINT#$PROFILE_NAME-$DOMAIN-Reality-$SNI-$UUID"

print_qr_and_url "$QR_TYPE" "$URL"
