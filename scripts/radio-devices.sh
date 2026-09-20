#!/usr/bin/env bash
# Baseline inspection for one gateway: what the protocol service holds, and how fresh it
# is. Read-only — it subscribes and reports, and changes nothing.
#
#   scripts/radio-devices.sh <host-alias> <role> [inventory]
#
# Service health and device responsiveness are reported separately on purpose. A healthy
# service with a silent device is a normal and important state, and collapsing the two is
# how an estate looks fine while it has stopped observing anything.
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=scripts/lib-inventory.sh
lab_usage='make radio-devices HOST=<alias> ROLE=<zigbee|zwave> [INVENTORY=<path>] [WINDOW=<seconds>]'
. scripts/lib-inventory.sh

resolve_gateway "${1:-}" "${2:-}" "${3:-}"
WINDOW=${WINDOW:-45}

printf '== radio devices: %s (role=%s) ==\n' "$HOST" "$ROLE"
printf 'observation window: %ss\n' "$WINDOW"

case "$ROLE" in
  zigbee) topic='zigbee2mqtt/#' ;;
  zwave)  topic='zwavejs/#' ;;
esac

# One subscription, everything derived from it. Sampling the same stream for the whole
# window is what makes the freshness verdict meaningful: a field that never changes over
# many messages is not being re-measured, however healthy the messages look.
capture=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" \
  "sudo timeout $((WINDOW + 8)) docker exec ff-lab-mosquitto \
     mosquitto_sub -h 127.0.0.1 -t '$topic' -v -W $WINDOW" 2>/dev/null || true)

if [ -z "$capture" ]; then
  printf '\nFAIL nothing was published on %s in %ss.\n' "$topic" "$WINDOW"
  printf '     The broker may be up while the protocol service publishes nothing —\n'
  printf '     a gateway that is running and reporting an empty estate.\n'
  exit 1
fi

printf '%s' "$capture" | ROLE="$ROLE" WINDOW="$WINDOW" python3 scripts/radio-report.py
