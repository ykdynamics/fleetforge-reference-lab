# Shared host/role/inventory resolution for the lab's operator commands.
#
# Sourced, never executed. Every target that names a gateway resolves it the same way,
# so preflight and provisioning cannot disagree about what a host alias means.
#
# Ansible is the single reader of the inventory format: resolving through
# ansible-inventory means a shell helper can never drift from what a playbook sees.
#
# On success it sets: INVENTORY HOST ROLE SSH_HOST SSH_USER TARGET
#                     RADIO_ADAPTER RADIO_ADAPTER_DRIVER LAB_ROOT MQTT_PORT UI_PORT

# shellcheck shell=bash

lab_usage=${lab_usage:-'make <target> HOST=<alias> ROLE=<zigbee|zwave> [INVENTORY=<path>]'}

die_usage() {
  printf 'FAIL %s\n' "$1" >&2
  printf 'usage: %s\n' "$lab_usage" >&2
  exit 2
}

# lab_field <dotted.key> — read one value out of the resolved host vars.
lab_field() {
  printf '%s' "$lab_hostvars" | python3 -c '
import json, sys
d = json.load(sys.stdin)
cur = d
for part in sys.argv[1].split("."):
    if not isinstance(cur, dict) or part not in cur:
        print(""); raise SystemExit
    cur = cur[part]
print("" if cur is None else cur)
' "$1"
}

# resolve_gateway <host> <role> [inventory]
#
# SC2034: everything this function assigns is its output — set here, read by the script
# that sourced it. That is the point of the file, so the "unused" warning is expected.
# shellcheck disable=SC2034
resolve_gateway() {
  HOST=${1:-}
  ROLE=${2:-}
  INVENTORY=${3:-}

  # Selection is explicit for every target. There is deliberately no default host:
  # the lab never guesses which gateway you meant.
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

  if ! lab_hostvars=$(ansible-inventory -i "$INVENTORY" --host "$HOST" 2>/dev/null); then
    printf 'FAIL host %s is not in %s\n' "$HOST" "$INVENTORY" >&2
    printf 'known hosts: %s\n' "$(ansible-inventory -i "$INVENTORY" --list 2>/dev/null \
      | python3 -c 'import json,sys; d=json.load(sys.stdin); print(", ".join(sorted(d.get("_meta",{}).get("hostvars",{}))) or "(none)")' 2>/dev/null || echo '(could not be listed)')" >&2
    exit 2
  fi

  local inv_role
  inv_role=$(lab_field role)
  # A role that disagrees with the inventory is a mistake worth stopping for: it is how
  # you act on the Zigbee gateway while believing you addressed the Z-Wave one.
  if [ -n "$inv_role" ] && [ "$inv_role" != "$ROLE" ]; then
    printf 'FAIL ROLE=%s but the inventory says %s is role %s\n' "$ROLE" "$HOST" "$inv_role" >&2
    exit 2
  fi

  SSH_HOST=$(lab_field ansible_host)
  SSH_USER=$(lab_field ansible_user)
  RADIO_ADAPTER=$(lab_field radio_adapter)
  RADIO_ADAPTER_DRIVER=$(lab_field radio_adapter_driver)
  LAB_ROOT=$(lab_field lab_root)
  LAB_ROOT=${LAB_ROOT:-/opt/fleetforge-lab}
  UI_PORT=$(lab_field protocol_ui_port)

  local mqtt_endpoint
  mqtt_endpoint=$(lab_field mqtt_endpoint)
  MQTT_PORT=${mqtt_endpoint##*:}
  [ "$MQTT_PORT" = "$mqtt_endpoint" ] && MQTT_PORT=1883

  TARGET=${SSH_HOST:-$HOST}
  [ -n "$SSH_USER" ] && TARGET="${SSH_USER}@${TARGET}"
}
