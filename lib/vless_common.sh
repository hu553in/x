#!/usr/bin/env bash

need_cmd() {
	command -v "$1" >/dev/null 2>&1
}

ensure_cmd() {
	if ! need_cmd "$1"; then
		printf 'Missing command: %s\n' "$1" >&2
		exit 1
	fi
}

maybe_print_help() {
	local action="${1:-}"

	if [[ "$action" == "-h" || "$action" == "--help" ]]; then
		"$2"
		exit 0
	fi
}

generate_uuid() {
	if need_cmd xray; then
		xray uuid
		return
	fi

	if [[ -r /proc/sys/kernel/random/uuid ]]; then
		cat /proc/sys/kernel/random/uuid
		return
	fi

	python3 - <<'PY'
import uuid
print(uuid.uuid4())
PY
}

url_encode() {
	URL_ENCODE_VALUE="$1" python3 - <<'PY'
import os
import urllib.parse

print(urllib.parse.quote(os.environ["URL_ENCODE_VALUE"], safe=""))
PY
}

print_qr_and_url() {
	local qr_type="$1"
	local url="$2"

	qrencode -t "$qr_type" "$url"
	printf '%s\n' "$url"
}

resolve_domain() {
	local domain="$1"
	local nginx_conf="$2"

	if [[ -n "$domain" ]]; then
		printf '%s\n' "$domain"
		return
	fi

	if [[ -f "$nginx_conf" ]]; then
		awk '/server_name[[:space:]]+/ {gsub(/;/, "", $2); print $2; exit}' "$nginx_conf"
		return
	fi

	printf 'Set DOMAIN to build the public link.\n' >&2
	exit 1
}

get_reality_public_key() {
	local private_key="$1"
	local out

	out="$(xray x25519 -i "$private_key")"
	printf '%s\n' "$out" | awk -F': ' '/^(Password|PublicKey):/ {print $2; exit}'
}
