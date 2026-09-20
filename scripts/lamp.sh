#!/usr/bin/env bash
# Switch one named lamp through its protocol service, and record the outcome honestly.
#
#   ACTION=off|on scripts/lamp.sh <host-alias> <role> <device-alias> [inventory]
#
# This is the STANDALONE path: the protocol service's own interface, no FleetForge.
# It switches exactly the device you name, reports what the device said afterwards, and
# asks what you actually saw. It never retries and never toggles twice.
set -euo pipefail

cd "$(dirname "$0")/.."

ACTION=${ACTION:?ACTION=off|on is required}
case "$ACTION" in off|on) ;; *) echo "FAIL ACTION must be off or on" >&2; exit 2 ;; esac

# shellcheck source=scripts/lib-inventory.sh
lab_usage='make lamp-off|lamp-on HOST=<alias> ROLE=<zigbee|zwave> DEVICE=<alias> [INVENTORY=<path>]'
. scripts/lib-inventory.sh

resolve_gateway "${1:-}" "${2:-}" "${4:-}"
DEVICE=${3:-}
[ -n "$DEVICE" ] || die_usage 'DEVICE= is required (the device alias from your inventory)'

# Find the named device on this host. No default, and no "first device" fallback: this
# command switches real mains hardware, so it acts only on a device you named.
device_json=$(printf '%s' "$lab_hostvars" | DEVICE="$DEVICE" python3 -c '
import json, os, sys
devices = (json.load(sys.stdin) or {}).get("devices") or []
for d in devices:
    if d.get("alias") == os.environ["DEVICE"]:
        print(json.dumps(d)); break
')
if [ -z "$device_json" ]; then
  printf 'FAIL device %s is not listed on %s in %s\n' "$DEVICE" "$HOST" "$INVENTORY" >&2
  printf 'known devices: %s\n' "$(printf '%s' "$lab_hostvars" | python3 -c '
import json,sys
print(", ".join(d.get("alias","?") for d in ((json.load(sys.stdin) or {}).get("devices") or [])) or "(none)")')" >&2
  exit 2
fi

ref=$(printf '%s' "$device_json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("protocol_ref",""))')
[ -n "$ref" ] || die_usage "device $DEVICE has no protocol_ref in the inventory"

# Each protocol is addressed its own way. A Zigbee device takes a state string on its own
# topic; a Z-Wave device takes a boolean on a command-class value topic. Writing this out
# per role rather than abstracting it is deliberate -- the difference is the lesson.
case "$ROLE" in
  zigbee)
    set_topic="$ref/set"
    state_topic="$ref"
    payload=$([ "$ACTION" = off ] && echo '{"state":"OFF"}' || echo '{"state":"ON"}')
    # The payload carries dozens of fields, most irrelevant here. Summarise the ones the
    # exercise is about, so the record stays readable and reviewable.
    summarise='state=%s power=%s current=%s:state,power,current'
    ;;
  zwave)
    set_topic="$ref/37/0/targetValue/set"
    state_topic="$ref/37/0/currentValue"
    payload=$([ "$ACTION" = off ] && echo '{"value":false}' || echo '{"value":true}')
    summarise='value=%s:value'
    ;;
esac

remote() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" "$@"; }

# Reduce a device payload to the fields this exercise is about.
brief() {
  [ -n "$1" ] || { printf '(none)'; return; }
  printf '%s' "$1" | SUMMARISE="$summarise" python3 -c '
import json, os, sys
fmt, _, keys = os.environ["SUMMARISE"].partition(":")
try:
    d = json.load(sys.stdin)
except Exception:
    print(sys.stdin.read().strip() or "(unparseable)"); raise SystemExit
print(fmt % tuple(d.get(k) for k in keys.split(",")))
'
}
mq() { remote "sudo docker exec ff-lab-mosquitto $*"; }

printf '== lamp %s: %s on %s (role=%s) ==\n' "$ACTION" "$DEVICE" "$HOST" "$ROLE"
printf 'path:     the protocol service, over its own MQTT interface (no FleetForge)\n'
printf 'topic:    %s\n' "$set_topic"
printf 'payload:  %s\n\n' "$payload"

before=$(mq "mosquitto_sub -h 127.0.0.1 -t '$state_topic' -C 1 -W 6" 2>/dev/null || true)
printf 'before:   %s\n' "$(brief "$before")"

mq "mosquitto_pub -h 127.0.0.1 -t '$set_topic' -m '$payload'"
printf 'sent:     request published\n'

sleep 5
after=$(mq "mosquitto_sub -h 127.0.0.1 -t '$state_topic' -C 1 -W 6" 2>/dev/null || true)
printf 'after:    %s\n\n' "$(brief "$after")"

# The record. Whatever the device says, the physical outcome needs a witness -- so ask for
# one, and accept not having one. WITNESS= makes it non-interactive without inventing an
# observation.
witness=${WITNESS:-}
if [ -z "$witness" ] && [ -t 0 ]; then
  printf 'Look at the lamp. Did it go %s? [y/n/unsure] ' "$ACTION"
  read -r answer
  case "$answer" in
    y|Y|yes) witness=observed ;;
    n|N|no)  witness=contradicted ;;
    *)       witness=unknown ;;
  esac
fi

case "$witness" in
  observed)     outcome=PASS;    note="operator reported the lamp went $ACTION" ;;
  contradicted) outcome=FAIL;    note="operator reported the lamp did NOT go $ACTION" ;;
  *)            outcome=UNKNOWN; note='no human observation recorded' ;;
esac

cat <<REPORT
-- outcome record --
what was asked   switch $DEVICE $ACTION via $set_topic
receipts         none — the standalone path issues no run or command identifier
device-reported  $(brief "$after")
human-observed   $note
outcome          $outcome — witness: $( [ "$outcome" = UNKNOWN ] && echo none || echo human-observed )
REPORT

if [ "$outcome" = UNKNOWN ]; then
  cat <<'NOTE'

The request succeeded and nobody confirmed the effect. That is an UNKNOWN outcome,
not a failure of the exercise — the device's own report is an echo of what it was
asked, not an independent witness. Do not switch again to "check": that is a second
physical operation and it destroys the evidence you were collecting.
NOTE
fi

[ "$outcome" = FAIL ] && exit 1
exit 0
