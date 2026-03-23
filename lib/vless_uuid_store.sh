#!/usr/bin/env bash

append_uuid_to_config() {
	local config_path="$1"
	local new_uuid="$2"
	local client_flow="$3"

	UUID_TO_ADD="$new_uuid" CONFIG_PATH="$config_path" CLIENT_FLOW="$client_flow" python3 - <<'PY'
import json
import os
from pathlib import Path

config_path = Path(os.environ["CONFIG_PATH"])
uuid_to_add = os.environ["UUID_TO_ADD"]
client_flow = os.environ["CLIENT_FLOW"]

data = json.loads(config_path.read_text())
clients = data["inbounds"][0]["settings"]["clients"]

if any(client.get("id") == uuid_to_add for client in clients):
    raise SystemExit(f"UUID already exists: {uuid_to_add}")

if client_flow == "__AUTO__":
    client_flow = clients[0].get("flow", "") if clients else ""

clients.append({"id": uuid_to_add, "flow": client_flow})
config_path.write_text(json.dumps(data, indent=4) + "\n")
PY
}

read_uuid_profile() {
	local config_path="$1"
	local target_uuid="$2"

	TARGET_UUID="$target_uuid" CONFIG_PATH="$config_path" python3 - <<'PY'
import json
import os
from pathlib import Path
from urllib.parse import quote

config_path = Path(os.environ["CONFIG_PATH"])
target_uuid = os.environ["TARGET_UUID"]

data = json.loads(config_path.read_text())
inbound = data["inbounds"][0]
clients = inbound["settings"]["clients"]

if not any(client.get("id") == target_uuid for client in clients):
    raise SystemExit(f"UUID not found: {target_uuid}")

stream = inbound["streamSettings"]
security = stream["security"]
xhttp = stream["xhttpSettings"]
path = quote(xhttp["path"], safe="")
mode = xhttp["mode"]
server_name = ""
short_id = ""
private_key = ""
port = str(inbound.get("port", 443))

if security == "reality":
    reality = stream["realitySettings"]
    server_name = reality["serverNames"][0]
    short_id = reality["shortIds"][0]
    private_key = reality["privateKey"]

print(f"security={security}")
print(f"path={path}")
print(f"mode={mode}")
print(f"server_name={server_name}")
print(f"short_id={short_id}")
print(f"private_key={private_key}")
print(f"port={port}")
PY
}
