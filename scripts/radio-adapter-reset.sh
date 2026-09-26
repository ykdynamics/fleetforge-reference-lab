#!/usr/bin/env bash
# Reset the radio adapter's own network, not just the service's copy of it.
#
#   scripts/radio-adapter-reset.sh <host-alias> <role> [inventory]   CONFIRM=<host>
#
# Why this exists. protocol-data-reset and host-reset clear what the protocol service
# stores. They cannot clear what the ADAPTER stores, and a Zigbee coordinator keeps its
# network in its own NVRAM. Wiping one side and not the other leaves the gateway unable
# to start at all:
#
#   error: network commissioning timed out - most likely network with the same panId
#          or extendedPanId already exists nearby
#
# The service tries to form a new network while the stick is still holding the old one.
# Not degraded: down. This target reconciles both sides.
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=scripts/lib-inventory.sh
lab_usage='make radio-adapter-reset HOST=<alias> ROLE=<zigbee|zwave> CONFIRM=<alias>'
. scripts/lib-inventory.sh

resolve_gateway "${1:-}" "${2:-}" "${3:-}"
CONFIRM=${CONFIRM:-}

case "$ROLE" in
  zigbee) service=zigbee2mqtt; data="$LAB_ROOT/data/zigbee2mqtt" ;;
  zwave)  service=zwave-js-ui; data="$LAB_ROOT/data/zwave-js-ui" ;;
esac

backups=0
if [ -n "${BACKUP_DIR:-}" ] && [ -d "$BACKUP_DIR" ]; then
  backups=$(find "$BACKUP_DIR" -maxdepth 1 -name "${HOST}-${ROLE}-*.tar.gz" | wc -l | tr -d ' ')
fi

cat <<EOF

== radio adapter reset: $HOST ($ROLE) ==

DESTROYS  the radio network held in the ADAPTER itself
DESTROYS  the protocol service's stored network and every pairing
          every device must be physically re-paired afterwards, by hand
KEEPS     the host, Docker, the FleetForge agent and its enrolment identity

This is the one reset a backup cannot undo. Restoring an archive re-creates the
service's files; it cannot put the old network back into a stick that has been
told to forget it. Use this when the two sides have diverged and the service
will not start, or when you deliberately want a new network.

backups found for this host/role in ${BACKUP_DIR:-<BACKUP_DIR not set>}: $backups
EOF

if [ "$CONFIRM" != "$HOST" ]; then
  printf '\nREFUSED this destroys the above on %s.\n' "$HOST" >&2
  printf 'Re-run with CONFIRM=%s to proceed. Nothing has been changed.\n' "$HOST" >&2
  exit 2
fi
printf '\nconfirmed for %s — proceeding\n\n' "$HOST"

remote() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" "$@"; }

case "$ROLE" in
  zigbee)
    # There is no bridge request that clears the coordinator's NVRAM, so the reconciliation
    # runs the other way: form a genuinely NEW network. The collision was a panId conflict,
    # so a new network needs new identifiers -- GENERATE for all three, which the service
    # supports and writes back itself on first start.
    printf -- '-- stopping %s --\n' "$service"
    remote "cd '$LAB_ROOT/compose' && docker compose --profile zigbee stop $service"
    printf -- '-- clearing the stored network --\n'
    remote "sudo rm -rf '$data' && sudo install -d -o \$(id -u) -g \$(id -g) -m 0750 '$data'"
    printf -- '-- seeding a configuration that forms a new network --\n'
    remote "sudo tee '$data/configuration.yaml' >/dev/null <<'CFG'
mqtt:
  server: mqtt://mosquitto:1883
  base_topic: zigbee2mqtt
serial:
  port: /dev/zigbee
  adapter: ${RADIO_ADAPTER_DRIVER:-zstack}
frontend:
  enabled: true
  port: 8080
advanced:
  network_key: GENERATE
  pan_id: GENERATE
  ext_pan_id: GENERATE
device_options:
  retain: true
onboarding: false
CFG
sudo chown \$(id -u):\$(id -g) '$data/configuration.yaml'"
    printf -- '-- starting %s --\n' "$service"
    remote "cd '$LAB_ROOT/compose' && docker compose --profile zigbee start $service"
    ;;
  zwave)
    # Z-Wave JS UI exposes the controller's own factory reset over its MQTT API, which is
    # the genuine adapter-side reset: the controller forgets its home id and every node.
    api="zwavejs/_CLIENTS/ZWAVE_GATEWAY-${HOST}/api"
    # The controller's home id BEFORE the reset. This, not the API reply, is what tells us
    # whether the reset happened -- see below.
    before_home=$(remote "sudo ls /opt/fleetforge-lab/data/zwave-js-ui/ 2>/dev/null | grep -oE '^[0-9a-f]{8}' | sort -u | tr '\n' ' '" || true)
    printf -- '-- asking the controller to factory reset (home id before: %s) --\n' "${before_home:-unknown}"
    remote "sudo docker exec ff-lab-mosquitto mosquitto_pub -h 127.0.0.1 -t '$api/hardReset/set' -m '{\"args\":[]}'"

    # Do NOT verify from the API reply. hardReset() destroys the controller instance and
    # re-initialises it, so the reply path is torn down by the very operation it would
    # confirm: the service logs "hard reset succeeded" and then, milliseconds later,
    # "hard reset failed: The controller instance is being destroyed (ZW0111)" -- and it is
    # the second one that reaches the caller. Trusting it reports FAIL on a reset that
    # worked, which is worse than reporting nothing: it invites a retry of a destructive
    # operation, or leaves an operator believing a network they no longer have.
    #
    # Verify by outcome instead: a NEW home id, and the controller alone on it.
    printf -- '-- waiting for the controller to come back on a new network --\n'
    new_home=""
    for _ in $(seq 1 30); do
      sleep 4
      current=$(remote "sudo ls /opt/fleetforge-lab/data/zwave-js-ui/ 2>/dev/null | grep -oE '^[0-9a-f]{8}' | sort -u | tr '\n' ' '" || true)
      for h in $current; do
        case " $before_home " in
          *" $h "*) ;;
          *) new_home=$h ;;
        esac
      done
      [ -n "$new_home" ] && break
    done

    if [ -z "$new_home" ]; then
      printf '\nFAIL no new home id appeared within two minutes.\n' >&2
      printf '     The controller may or may not have reset. Check the driver log before\n' >&2
      printf '     retrying, because a second reset on an already-reset controller is not\n' >&2
      printf '     harmless -- it discards the network you just created.\n' >&2
      printf '       make stack-logs HOST=%s ROLE=%s\n' "$HOST" "$ROLE" >&2
      exit 1
    fi
    printf 'PASS the controller reset: new home id %s (was %s)\n' "$new_home" "${before_home:-unknown}"

    # The broker keeps the destroyed network's retained state, so every node of a network
    # that no longer exists still answers a subscribe. Left alone, the device inventory
    # lists hardware the controller has forgotten -- observed on the bench, where a node
    # showed as present with a lastActive ten hours old.
    printf -- '-- clearing retained topics for the old network --\n'
    cleared=$(remote "topics=\$(sudo timeout 12 docker exec ff-lab-mosquitto mosquitto_sub -h 127.0.0.1 -t 'zwavejs/#' -v -W 8 2>/dev/null | awk '{print \$1}' | grep -vE '_CLIENTS|/driver/' | sort -u)
      n=0
      for t in \$topics; do
        sudo docker exec ff-lab-mosquitto mosquitto_pub -h 127.0.0.1 -t \"\$t\" -r -n && n=\$((n+1))
      done
      echo \$n" || echo 0)
    printf 'cleared %s retained topic(s)\n' "${cleared:-0}"
    ;;
esac

printf -- '\n-- waiting for the service to come back --\n'
if remote "for i in \$(seq 1 40); do
     sudo docker logs $service 2>&1 | grep -qiE 'Zigbee2MQTT started|Driver ready' && exit 0
     sleep 3
   done; exit 1" 2>/dev/null; then
  printf 'PASS the service started on a new network\n'
else
  printf 'WARN the service did not report a successful start within two minutes.\n'
  printf '     Check: make stack-logs HOST=%s ROLE=%s\n' "$HOST" "$ROLE"
fi

cat <<EOF

The adapter and the service now agree on an empty network. Every device must be
re-paired from scratch:

  make radio-join-open HOST=$HOST ROLE=$ROLE MINUTES=2

Your inventory still lists the old device reference. Update protocol_ref after
re-pairing, or the lamp targets will address a device that no longer exists.
EOF
