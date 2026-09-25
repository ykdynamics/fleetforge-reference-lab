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
    printf -- '-- asking the controller to factory reset --\n'
    remote "sudo docker exec -d ff-lab-mosquitto sh -c \"mosquitto_sub -h 127.0.0.1 -t '$api/hardReset' -C 1 -W 25 > /tmp/hardreset.json 2>&1\""
    sleep 1
    remote "sudo docker exec ff-lab-mosquitto mosquitto_pub -h 127.0.0.1 -t '$api/hardReset/set' -m '{\"args\":[]}'"
    sleep 12
    reply=$(remote "sudo docker exec ff-lab-mosquitto cat /tmp/hardreset.json 2>/dev/null" || true)
    ok=$(printf '%s' "$reply" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("success"))' 2>/dev/null || echo unknown)
    if [ "$ok" != True ]; then
      msg=$(printf '%s' "$reply" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("message",""))' 2>/dev/null || true)
      printf '\nFAIL the controller did not confirm the reset: %s\n' "${msg:-no reply within 12s}" >&2
      printf '     Treat the adapter as unchanged and investigate before retrying.\n' >&2
      exit 1
    fi
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
