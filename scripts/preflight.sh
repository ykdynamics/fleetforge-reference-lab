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

# shellcheck source=scripts/lib-inventory.sh
lab_usage='make preflight HOST=<alias> ROLE=<zigbee|zwave> [INVENTORY=<path>]'
. scripts/lib-inventory.sh

resolve_gateway "${1:-}" "${2:-}" "${3:-}"

printf '== preflight %s (role=%s) ==\n' "$HOST" "$ROLE"
printf 'inventory: %s\n' "$INVENTORY"
printf 'target:    %s\n\n' "$TARGET"

# BatchMode: fail immediately rather than sitting on a password prompt.
set +e
ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$TARGET" \
  "ROLE='$ROLE' RADIO_ADAPTER='$RADIO_ADAPTER' LAB_ROOT='$LAB_ROOT' MQTT_PORT='$MQTT_PORT' UI_PORT='$UI_PORT' sh -s" \
  < scripts/preflight-remote.sh
status=$?
set -e

if [ "$status" -eq 255 ]; then
  printf '\nFAIL could not reach %s over SSH — check the address, the key and that the host is booted\n' "$TARGET" >&2
  exit 1
fi

exit "$status"
