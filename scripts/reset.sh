#!/usr/bin/env bash
# The four resets. They destroy different things, and conflating them is how somebody
# wipes a radio network while meaning to restart an agent.
#
#   ACTION=scenario-restore     HOST= ROLE= DEVICE=          nothing destroyed
#   ACTION=agent-remove         HOST= CONFIRM=HOST           agent only
#   ACTION=protocol-data-reset  HOST= ROLE= CONFIRM=HOST     radio network and pairings
#   ACTION=host-reset           HOST= CONFIRM=HOST           everything the lab installed
#
# Rules every action here obeys:
#   - one named host at a time; no list, no "all", no discovery
#   - destructive actions print what will be lost BEFORE doing it
#   - destructive actions require CONFIRM to equal HOST
#   - the control plane is never reset from here; retiring a stale gateway record is
#     done deliberately through FleetForge's own interface
set -euo pipefail

cd "$(dirname "$0")/.."

ACTION=${ACTION:?ACTION is required}

# shellcheck source=scripts/lib-inventory.sh
lab_usage='make scenario-restore|agent-remove|protocol-data-reset|host-reset HOST=<alias> [ROLE=] [DEVICE=] [CONFIRM=<alias>]'
. scripts/lib-inventory.sh

# ROLE is irrelevant to the agent and host resets, but resolve_gateway wants one. Take it
# from the inventory so those two can be called with HOST alone.
role_arg=${2:-}
if [ -z "$role_arg" ] && [ -n "${1:-}" ]; then
  role_arg=$(ANSIBLE_CONFIG=ansible/ansible.cfg ansible-inventory \
    -i "${3:-inventory/inventory.yml}" --host "$1" 2>/dev/null \
    | python3 -c 'import json,sys; print((json.load(sys.stdin) or {}).get("role",""))' 2>/dev/null || true)
fi
resolve_gateway "${1:-}" "$role_arg" "${3:-}"

CONFIRM=${CONFIRM:-}
DEVICE=${DEVICE:-}
PURGE_IDENTITY=${PURGE_IDENTITY:-}

remote() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" "$@"; }

# Nothing destructive happens until this has passed. The confirmation must NAME the host,
# so "wrong window, right command" stops being a single keystroke away from a wiped mesh.
require_confirmation() {
  printf '\n%s\n' "$1"
  if [ "$CONFIRM" != "$HOST" ]; then
    printf '\nREFUSED this destroys the above on %s.\n' "$HOST" >&2
    printf 'Re-run with CONFIRM=%s to proceed. Nothing has been changed.\n' "$HOST" >&2
    exit 2
  fi
  printf '\nconfirmed for %s — proceeding\n\n' "$HOST"
}

case "$ACTION" in

  scenario-restore)
    # The safe one, and the one you want almost every time: put the lamp back to its
    # documented baseline. Destroys nothing and needs no confirmation.
    [ -n "$DEVICE" ] || die_usage 'DEVICE= is required (the device alias from your inventory)'
    printf '== scenario restore: %s on %s ==\n' "$DEVICE" "$HOST"
    printf 'baseline: lamp lit\n\n'
    ACTION=on exec ./scripts/lamp.sh "$HOST" "$ROLE" "$DEVICE" "${3:-}"
    ;;

  agent-remove)
    # Built before the heredoc rather than inside it. A command substitution nested in a
    # heredoc is a parser puzzle nobody should have to solve while reading a destructive
    # command.
    identity_note="KEEPS     the enrolment identity at /var/lib/fleetforge/agent.json"
    if [ -n "$PURGE_IDENTITY" ]; then
      identity_note="DESTROYS  the enrolment identity — PURGE_IDENTITY=1 is set, so this host will
          enrol as a NEW gateway next time, leaving the old record behind in the
          control plane for you to retire"
    fi
    require_confirmation "$(cat <<EOF
== agent removal: $HOST ==

REMOVES   the FleetForge agent package, its service and /etc/fleetforge/agent.env
KEEPS     the radio stack, every pairing, all protocol data
$identity_note

You do not need this to see the standalone estate. It is still there underneath a
working agent — remove the agent because you want it gone, not to illustrate something.
EOF
)"
    remote "sudo systemctl disable --now ffagent 2>/dev/null || true
      sudo apt-get remove -y -qq fleetforge-agent 2>/dev/null || sudo dpkg -r fleetforge-agent || true
      sudo rm -f /etc/fleetforge/agent.env
      $([ -n "$PURGE_IDENTITY" ] && echo 'sudo rm -f /var/lib/fleetforge/agent.json')"
    printf '\n-- after --\n'
    remote "dpkg-query -W -f='package: \${Status}\n' fleetforge-agent 2>/dev/null || echo 'package: removed'
      if sudo test -f /var/lib/fleetforge/agent.json; then
        echo 'identity: preserved'
      else
        echo 'identity: absent — this host will enrol as a NEW gateway'
      fi"
    printf '\nThe radio stack and every pairing are untouched. Verify with:\n'
    printf '  make radio-devices HOST=%s ROLE=%s\n' "$HOST" "$ROLE"
    ;;

  protocol-data-reset)
    # Guarded rather than piped from a find that may fail: under `set -o pipefail` a
    # find against a missing directory takes the whole script down with it, and the
    # operator loses the no-backup warning precisely when they are about to destroy a
    # radio network without one.
    backups=0
    if [ -n "${BACKUP_DIR:-}" ] && [ -d "$BACKUP_DIR" ]; then
      backups=$(find "$BACKUP_DIR" -maxdepth 1 -name "${HOST}-${ROLE}-*.tar.gz" | wc -l | tr -d ' ')
    fi
    backup_note="backups found for this host/role in ${BACKUP_DIR:-<BACKUP_DIR not set>}: $backups"
    if [ "$backups" = 0 ]; then
      backup_note="$backup_note

WARNING   no backup was found. A backup restores the service state; it is not a
          promise the mesh returns, because some adapters hold network identity in
          the adapter itself. Take one anyway:
            make radio-backup HOST=$HOST ROLE=$ROLE BACKUP_DIR=<private path> STOP_SERVICES=1"
    fi
    require_confirmation "$(cat <<EOF
== protocol data reset: $HOST ($ROLE) ==

DESTROYS  the protocol service's persistent data
DESTROYS  the radio network and EVERY PAIRING on this gateway
          every device must be physically re-paired afterwards, by hand, one at a time
KEEPS     the host, Docker, the FleetForge agent and its enrolment identity

$backup_note
EOF
)"
    case "$ROLE" in zigbee) service=zigbee2mqtt ;; zwave) service=zwave-js-ui ;; esac
    remote "cd '$LAB_ROOT/compose' && docker compose --profile '$ROLE' stop $service
      sudo rm -rf '$LAB_ROOT/data/$service'
      sudo install -d -o \$(id -u) -g \$(id -g) -m 0750 '$LAB_ROOT/data/$service'"
    printf '\nProtocol data removed. The service is stopped and its data directory is empty.\n'
    printf 'Bring it back and re-pair from scratch:\n'
    printf '  make stack-up HOST=%s ROLE=%s\n' "$HOST" "$ROLE"
    ;;

  host-reset)
    require_confirmation "$(cat <<EOF
== full host reset: $HOST ==

DESTROYS  the FleetForge agent AND its enrolment identity
DESTROYS  the protocol stack, its containers and ALL protocol data
DESTROYS  the radio network and every pairing on this gateway
DESTROYS  the lab directories under $LAB_ROOT
KEEPS     the operating system and your SSH access

The host is left ready to be provisioned again from chapter 2. Use this on hardware you
are willing to rebuild — it is the right tool for qualifying the walkthrough from a
clean start, and the wrong tool for almost anything else.

A stale gateway record may be left behind in the control plane. Retire it there,
deliberately: this command does not touch the control plane.
EOF
)"
    remote "sudo systemctl disable --now ffagent 2>/dev/null || true
      sudo apt-get remove -y -qq fleetforge-agent 2>/dev/null || sudo dpkg -r fleetforge-agent || true
      if [ -d '$LAB_ROOT/compose' ]; then
        cd '$LAB_ROOT/compose' && docker compose --profile zigbee --profile zwave down --remove-orphans || true
      fi
      sudo rm -rf /etc/fleetforge /var/lib/fleetforge '$LAB_ROOT'"
    printf '\n-- after --\n'
    remote "test -d '$LAB_ROOT' && echo 'lab root: still present' || echo 'lab root: removed'
      docker ps --filter name=ff-lab- --format '{{.Names}}' | grep . && echo '(containers above still running)' || echo 'containers: none'"
    printf '\nProvision it again with:\n  make preflight HOST=%s ROLE=%s\n  make provision HOST=%s ROLE=%s\n' \
      "$HOST" "$ROLE" "$HOST" "$ROLE"
    ;;

  *)
    printf 'FAIL unknown ACTION: %s\n' "$ACTION" >&2
    exit 2
    ;;
esac
