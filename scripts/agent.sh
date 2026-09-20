#!/usr/bin/env bash
# Install or inspect the FleetForge agent on one gateway.
#
#   ACTION=plan|install|status scripts/agent.sh <host-alias> <role> [inventory]
#
# plan     reads   what installing would change, and whether this host is already enrolled
# install  mutates installs and enrols, PRESERVING any existing gateway identity
# status   reads   agent version, last-cycle result and the non-secret collector settings
set -euo pipefail

cd "$(dirname "$0")/.."

ACTION=${ACTION:-status}

# shellcheck source=scripts/lib-inventory.sh
lab_usage='make agent-plan|agent-install|agent-status HOST=<alias> ROLE=<zigbee|zwave> [INVENTORY=<path>]'
. scripts/lib-inventory.sh

resolve_gateway "${1:-}" "${2:-}" "${3:-}"

play() {
  ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
    -i "$INVENTORY" --limit "$HOST" "$@" ansible/playbooks/gateway-agent.yml
}

printf '== agent %s: %s (role=%s) ==\n' "$ACTION" "$HOST" "$ROLE"

case "$ACTION" in
  # JSON, so the value arrives as a boolean. `-e var=true` passes the STRING "true",
  # and Ansible rejects a non-boolean conditional.
  plan)    play -e '{"agent_plan_only": true}' ;;
  install) play ;;
  status)
    # Never prints the token or the enrolment file's contents -- only whether they exist
    # and what the agent is doing.
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" '
      printf -- "-- package --\n"
      dpkg-query -W -f="${Package} ${Version}\n" fleetforge-agent 2>/dev/null || echo "(not installed)"
      printf -- "\n-- unit --\n"
      systemctl show ffagent -p ActiveState -p Result -p ExecMainStatus 2>/dev/null || echo "(no unit)"
      printf -- "\n-- enrolment identity --\n"
      if sudo test -f /var/lib/fleetforge/agent.json; then
        printf "PASS enrolment state file present (contents not shown)\n"
      else
        printf "WARN no enrolment state file — this gateway is not enrolled\n"
      fi
      printf -- "\n-- collector settings (non-secret only) --\n"
      sudo grep -E "^FLEETFORGE_AGENT_(ZIGBEE2MQTT|ZWAVEJS|DISPLAY_NAME|STATE_FILE|CONTROL_PLANE_URL)" \
        /etc/fleetforge/agent.env 2>/dev/null || echo "(no agent.env)"
      printf -- "\n-- recent agent log --\n"
      sudo journalctl -u ffagent -n 12 --no-pager 2>/dev/null | tail -12 || echo "(no journal)"
    '
    ;;
  *) printf 'FAIL ACTION must be plan, install or status — not %s\n' "$ACTION" >&2; exit 2 ;;
esac
