#!/usr/bin/env bash

set -euxo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/vless_common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/vless_uuid_store.sh"

CONFIG_PATH="${CONFIG_PATH:-/usr/local/etc/xray/config.json}"
NGINX_CONF="${NGINX_CONF:-/etc/nginx/conf.d/xray.conf}"
DOMAIN="${DOMAIN:-x.example.com}"
XRAY_SERVICE="${XRAY_SERVICE:-xray}"
CLIENT_FLOW="${CLIENT_FLOW:-__AUTO__}"
QR_TYPE="${QR_TYPE:-ANSIUTF8}"
CLIENT_FINGERPRINT="${CLIENT_FINGERPRINT:-chrome}"
PROFILE_NAME="${PROFILE_NAME:-XHTTP}"
TLS_SECURITY="${TLS_SECURITY:-tls}"

usage() {
	cat <<'EOF'
Usage:
  ./vless_xhttp_uuid.sh add [uuid]
  ./vless_xhttp_uuid.sh show <uuid>

Environment overrides:
  DOMAIN             Public hostname for the generated vless:// link.
  CONFIG_PATH        Xray config path.
  NGINX_CONF         Nginx config path for TLS mode auto-detection.
  XRAY_SERVICE       Service name to restart after add.
  CLIENT_FLOW        Flow for newly added UUIDs. `__AUTO__` copies the first client.
  QR_TYPE            qrencode output type.
  CLIENT_FINGERPRINT Client fingerprint in the generated vless:// link.
  PROFILE_NAME       Link label prefix after #.
  TLS_SECURITY       Security parameter for non-Reality links.
EOF
}

build_url() {
	local target_uuid="$1"
	local domain="$2"
	local security="$3"
	local path="$4"
	local mode="$5"
	local server_name="$6"
	local short_id="$7"
	local private_key="$8"
	local port="$9"

	if [[ "$security" == "none" ]]; then
		printf 'vless://%s@%s:%s?security=%s&sni=%s&alpn=h3&type=xhttp&path=%s&mode=%s&encryption=none&fp=%s#%s-%s-%s\n' \
			"$target_uuid" "$domain" "$port" "$TLS_SECURITY" "$domain" "$path" "$mode" "$CLIENT_FINGERPRINT" "$PROFILE_NAME" "$domain" "$target_uuid"
		return
	fi

	if [[ "$security" == "reality" ]]; then
		local public_key
		public_key="$(get_reality_public_key "$private_key")"

		printf 'vless://%s@%s:%s?security=reality&sni=%s&alpn=h3&type=xhttp&path=%s&mode=%s&encryption=none&pbk=%s&sid=%s&fp=%s#%s-%s-Reality-%s-%s\n' \
			"$target_uuid" "$domain" "$port" "$server_name" "$path" "$mode" "$public_key" "$short_id" "$CLIENT_FINGERPRINT" "$PROFILE_NAME" "$domain" "$server_name" "$target_uuid"
		return
	fi

	printf 'Unsupported security mode: %s\n' "$security" >&2
	exit 1
}

main() {
	local action="${1:-}"

	if [[ -z "$action" ]]; then
		usage
		exit 1
	fi
	maybe_print_help "$action" usage

	ensure_cmd python3
	ensure_cmd qrencode

	if [[ ! -f "$CONFIG_PATH" ]]; then
		printf 'Config not found: %s\n' "$CONFIG_PATH" >&2
		exit 1
	fi

	case "$action" in
	add)
		local target_uuid="${2:-}"
		if [[ -z "$target_uuid" ]]; then
			target_uuid="$(generate_uuid)"
		fi
		append_uuid_to_config "$CONFIG_PATH" "$target_uuid" "$CLIENT_FLOW"
		systemctl restart "$XRAY_SERVICE"
		;;
	show)
		local target_uuid="${2:-}"
		if [[ -z "$target_uuid" ]]; then
			usage
			exit 1
		fi
		;;
	*)
		usage
		exit 1
		;;
	esac

	local profile
	profile="$(read_uuid_profile "$CONFIG_PATH" "$target_uuid")"

	local security=""
	local path=""
	local mode=""
	local server_name=""
	local short_id=""
	local private_key=""
	local port=""

	while IFS='=' read -r key value; do
		case "$key" in
		security) security="$value" ;;
		path) path="$value" ;;
		mode) mode="$value" ;;
		server_name) server_name="$value" ;;
		short_id) short_id="$value" ;;
		private_key) private_key="$value" ;;
		port) port="$value" ;;
		esac
	done <<<"$profile"

	local domain
	domain="$(resolve_domain "$DOMAIN" "$NGINX_CONF")"

	local url
	url="$(build_url "$target_uuid" "$domain" "$security" "$path" "$mode" "$server_name" "$short_id" "$private_key" "$port")"

	print_qr_and_url "$QR_TYPE" "$url"
}

main "$@"
