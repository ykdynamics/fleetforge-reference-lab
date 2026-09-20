#!/usr/bin/env bash
# Read-only gateway preflight — the part that runs on YOUR machine.
#
#   scripts/preflight.sh <host-alias> <role> [inventory-path]
#
# Resolves the host from your inventory, then runs scripts/preflight-remote.sh on it
# over SSH. Nothing is installed, started, stopped or changed on the gateway.
#
# Exit codes (see docs/command-contract.md):
#   0  every check was PASS or WARN
#   1  at least one check FAILed, or the host could not be reached
#   2  usage error — nothing was attempted
set -euo pipefail

cd "$(dirname "$0")/.."

die_usage() {
  printf 'FAIL %s\n' "$1" >&2
  printf 'usage: make preflight HOST=<alias> ROLE=<zigbee|zwave> [INVENTORY=<path>]\n' >&2
  exit 2
}

HOST=${1:-}
ROLE=${2:-}
INVENTORY=${3:-}

# Selection is explicit for every target. There is deliberately no default host: the
# lab never guesses which gateway you meant.
[ -n "$HOST" ] || die_usage 'HOST= is required (the host alias from your inventory)'
[ -n "$ROLE" ] || die_usage 'ROLE= is required (zigbee or zwave)'
case "$ROLE" in
  zigbee|zwave) ;;
  *) die_usage "ROLE must be 'zigbee' or 'zwave', not '$ROLE'" ;;
esac

if [ -z "$INVENTORY" ]; then
  for candidate in inventory/inventory.yml inventory/inventory.yaml; do
    [ -f "$candidate" ] && INVENTORY=$candidate && break
  done
fi
[ -n "$INVENTORY" ] || die_usage 'no inventory found — copy inventory/inventory.example.yml to inventory/inventory.yml, or pass INVENTORY=<path>'
[ -f "$INVENTORY" ] || die_usage "inventory not found: $INVENTORY"

command -v ansible-inventory >/dev/null 2>&1 || {
  printf 'FAIL ansible-inventory is required to resolve the inventory (Ansible is a documented prerequisite)\n' >&2
  exit 1
}

# Ansible is the single reader of the inventory format, so this cannot drift from what
# provisioning will later see.
if ! hostvars=$(ansible-inventory -i "$INVENTORY" --host "$HOST" 2>/dev/null); then
  printf 'FAIL host %s is not in %s\n' "$HOST" "$INVENTORY" >&2
  printf 'known hosts: %s\n' "$(ansible-inventory -i "$INVENTORY" --list 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(", ".join(sorted(d.get("_meta",{}).get("hostvars",{}))) or "(none)")' 2>/dev/null || echo '(could not be listed)')" >&2
  exit 2
fi

field() {
  printf '%s' "$hostvars" | python3 -c '
import json, sys
d = json.load(sys.stdin)
key = sys.argv[1]
cur = d
for part in key.split("."):
    if not isinstance(cur, dict) or part not in cur:
        print(""); raise SystemExit
    cur = cur[part]
print("" if cur is None else cur)
' "$1"
}

inv_role=$(field role)
ssh_host=$(field ansible_host)
ssh_user=$(field ansible_user)
radio_adapter=$(field radio_adapter)
lab_root=$(field lab_root)
mqtt_endpoint=$(field mqtt_endpoint)
ui_port=$(field protocol_ui_port)

# A role that disagrees with the inventory is a mistake worth stopping for: it is how
# you preflight the Zigbee gateway and conclude the Z-Wave one is fine.
if [ -n "$inv_role" ] && [ "$inv_role" != "$ROLE" ]; then
  printf 'FAIL ROLE=%s but the inventory says %s is role %s\n' "$ROLE" "$HOST" "$inv_role" >&2
  exit 2
fi

target=${ssh_host:-$HOST}
[ -n "$ssh_user" ] && target="${ssh_user}@${target}"

mqtt_port=${mqtt_endpoint##*:}
[ "$mqtt_port" = "$mqtt_endpoint" ] && mqtt_port=1883

printf '== preflight %s (role=%s) ==\n' "$HOST" "$ROLE"
printf 'inventory: %s\n' "$INVENTORY"
printf 'target:    %s\n\n' "$target"

# BatchMode: fail immediately rather than sitting on a password prompt.
set +e
ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$target" \
  "ROLE='$ROLE' RADIO_ADAPTER='$radio_adapter' LAB_ROOT='${lab_root:-/opt/fleetforge-lab}' MQTT_PORT='$mqtt_port' UI_PORT='$ui_port' sh -s" \
  < scripts/preflight-remote.sh
status=$?
set -e

if [ "$status" -eq 255 ]; then
  printf '\nFAIL could not reach %s over SSH — check the address, the key and that the host is booted\n' "$target" >&2
  exit 1
fi

exit "$status"
