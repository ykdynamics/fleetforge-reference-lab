#!/usr/bin/env bash
# Open or close the pairing window on ONE gateway.
#
#   ACTION=open  MINUTES=n scripts/radio-join.sh <host-alias> <role> [inventory]
#   ACTION=close           scripts/radio-join.sh <host-alias> <role> [inventory]
#
# Opening a join window is the one routine lab action that can affect a gateway you did
# not name: a device being factory-reset joins whichever coordinator is listening. With
# two coordinators in one room that is how a plug lands on the wrong gateway and nobody
# notices until the fleet view looks wrong. So this opens the window on the named host
# only, for a bounded time, and prints when it closes.
#
# Putting the device into its own join mode stays manual and physical. At this size
# automating it would hide the step that actually matters.
set -euo pipefail

cd "$(dirname "$0")/.."

ACTION=${ACTION:?ACTION=open|close is required}
MINUTES=${MINUTES:-2}

# shellcheck source=scripts/lib-inventory.sh
lab_usage='make radio-join-open|radio-join-close HOST=<alias> ROLE=<zigbee|zwave> [MINUTES=<n>]'
. scripts/lib-inventory.sh

resolve_gateway "${1:-}" "${2:-}" "${3:-}"

case "$ACTION" in
  open)
    case "$MINUTES" in
      ''|*[!0-9]*) die_usage "MINUTES must be a whole number, not '$MINUTES'" ;;
    esac
    if [ "$MINUTES" -lt 1 ] || [ "$MINUTES" -gt 15 ]; then
      die_usage "MINUTES must be between 1 and 15 — an unbounded window is how devices join the wrong gateway"
    fi
    ;;
  close) ;;
  *) printf 'FAIL ACTION must be open or close, not %s\n' "$ACTION" >&2; exit 2 ;;
esac

remote() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" "$@"; }
pub() { remote "sudo docker exec ff-lab-mosquitto mosquitto_pub -h 127.0.0.1 -t '$1' -m '$2'"; }

# Publishing is not doing. The first version of this reported OPEN whether or not the
# service accepted the request -- the exact confusion between a queued message and an
# effect that this lab spends its time separating everywhere else.
fail_unverified() {
  printf '\nFAIL the request was published but %s\n' "$1" >&2
  printf '     The pairing window is NOT open. Nothing is listening for a device.\n' >&2
  exit 1
}

printf '== pairing window %s: %s (role=%s) ==\n' "$ACTION" "$HOST" "$ROLE"

case "$ROLE" in
  zigbee)
    # Verified against the running service: bridge.js requires `time` in seconds and
    # rejects a payload without it. Zero closes the window.
    seconds=0
    [ "$ACTION" = open ] && seconds=$((MINUTES * 60))
    pub "zigbee2mqtt/bridge/request/permit_join" "{\"time\": $seconds}"
    sleep 3
    # The bridge publishes its own state; ask it rather than trusting the publish.
    state=$(remote "sudo docker exec ff-lab-mosquitto mosquitto_sub -h 127.0.0.1 -t 'zigbee2mqtt/bridge/info' -C 1 -W 8" 2>/dev/null |
      python3 -c 'import json,sys; print(json.load(sys.stdin).get("permit_join"))' 2>/dev/null || echo unknown)
    if [ "$ACTION" = open ] && [ "$state" != True ]; then
      fail_unverified "the bridge still reports permit_join=$state"
    fi
    if [ "$ACTION" = close ] && [ "$state" = True ]; then
      fail_unverified "the bridge still reports the window open"
    fi
    ;;
  zwave)
    # Z-Wave JS UI exposes its API over MQTT at
    #   <prefix>/_CLIENTS/<clientID>/api/<method>/set
    # with the client id built from the gateway name configured in its settings.
    api="zwavejs/_CLIENTS/ZWAVE_GATEWAY-${HOST}/api"
    method=stopInclusion
    args='[]'
    if [ "$ACTION" = open ]; then
      method=startInclusion
      # Two arguments, not one. startInclusion(strategy, options) dereferences
      # options.name with no default, so a single argument throws inside the service and
      # comes back as "Cannot read properties of undefined". 0 is the default strategy.
      args='[0, {}]'
    fi
    # Listen for the reply before asking, then read what the service actually said.
    remote "sudo docker exec -d ff-lab-mosquitto sh -c \"mosquitto_sub -h 127.0.0.1 -t '$api/$method' -C 1 -W 12 > /tmp/joinreply.json 2>&1\""
    sleep 1
    pub "$api/$method/set" "{\"args\":$args}"
    sleep 6
    reply=$(remote "sudo docker exec ff-lab-mosquitto cat /tmp/joinreply.json 2>/dev/null" || true)
    ok=$(printf '%s' "$reply" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("success"))' 2>/dev/null || echo unknown)
    if [ "$ok" != True ]; then
      msg=$(printf '%s' "$reply" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("message",""))' 2>/dev/null || true)
      fail_unverified "the service refused it: ${msg:-no reply within 6s}"
    fi
    ;;
esac

if [ "$ACTION" = open ]; then
  closes=$(date -u -v+"${MINUTES}"M '+%H:%M:%SZ' 2>/dev/null || date -u -d "+${MINUTES} minutes" '+%H:%M:%SZ' 2>/dev/null || echo "in ${MINUTES}m")
  cat <<EOF

OPEN on $HOST only, for ${MINUTES} minute(s) — closes about $closes UTC.

Now put the device into its own join mode: usually a button press pattern from its
manual. Watch the protocol service's UI for it to appear and identify itself.

Close the window as soon as it has joined, rather than waiting for the timeout:

  make radio-join-close HOST=$HOST ROLE=$ROLE

If you are running both roles, do not open a window on the other gateway while this
one is open.
EOF
else
  printf '\nCLOSED on %s. Safe to run when it was already closed.\n' "$HOST"
fi
