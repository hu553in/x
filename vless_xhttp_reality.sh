#!/usr/bin/env bash

set -euxo pipefail

UUID="11111111-1111-1111-1111-111111111111"
DOMAIN="x.example.com"
SNI="vk6-9.vkuser.net"

apt update
apt upgrade -y
apt autoremove -y --purge
apt install -y curl openssl qrencode

bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
xray version

OUT="$(xray x25519)"
PRIVATE_KEY="$(printf '%s\n' "$OUT" | awk -F': ' '/^PrivateKey:/ {print $2}')"
PUBLIC_KEY="$(printf '%s\n' "$OUT" | awk -F': ' '/^(Password|PublicKey):/ {print $2}')"
SHORT_ID="$(openssl rand -hex 8)"

cat >/usr/local/etc/xray/config.json <<EOF
{
    "log": {
        "loglevel": "warning",
        "access": "/var/log/xray/access.log",
        "error": "/var/log/xray/error.log"
    },
    "inbounds": [
        {
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "flow": ""
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "xhttp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "$SNI:443",
                    "xver": 0,
                    "serverNames": [
                        "$SNI"
                    ],
                    "privateKey": "$PRIVATE_KEY",
                    "shortIds": [
                        "$SHORT_ID"
                    ]
                },
                "xhttpSettings": {
                    "path": "/database",
                    "mode": "stream-one"
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": [
                    "http",
                    "tls",
                    "quic"
                ]
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

URL="vless://$UUID@$DOMAIN:443?security=reality&sni=$SNI&alpn=h3&type=xhttp&path=%2Fdatabase&mode=stream-one&encryption=none&pbk=$PUBLIC_KEY&sid=$SHORT_ID&fp=chrome#XHTTP-$DOMAIN-Reality-$SNI-$UUID"

qrencode -t ANSIUTF8 "$URL"
echo "$URL"
