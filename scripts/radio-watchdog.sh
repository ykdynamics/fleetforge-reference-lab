#!/usr/bin/env bash
# Operate one Zigbee gateway's radio watchdog (docs/radio-watchdog.md).
#
#   ACTION=install|status|dry-run|force scripts/radio-watchdog.sh <host-alias> <role> [inventory]
#
# install  mutates install uhubctl, the watchdog and its timer; the protocol stack is untouched
# status   reads   timer state, the last checks and the last recovery
# dry-run  reads   what a check would do right now (waits up to the silence window)
# force    mutates power-cycle the adapter now: a hardware test of the recovery itself
set -euo pipefail

cd "$(dirname "$0")/.."

ACTION=${ACTION:-status}

# shellcheck source=scripts/lib-inventory.sh
lab_usage='make radio-watchdog-<install|status|dry-run|force> HOST=<alias> ROLE=zigbee [INVENTORY=<path>]'
. scripts/lib-inventory.sh

resolve_gateway "${1:-}" "${2:-}" "${3:-}"
[ "$ROLE" = zigbee ] || { printf 'FAIL the radio watchdog is for Zigbee gateways, not %s\n' "$ROLE" >&2; exit 2; }

remote() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" "$@"
}

printf '== radio watchdog %s: %s ==\n' "$ACTION" "$HOST"

case "$ACTION" in
  install)
    ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
      -i "$INVENTORY" --limit "$HOST" ansible/playbooks/gateway-radio-watchdog.yml
    ;;
  status)
    remote "systemctl list-timers ff-lab-radio-watchdog.timer --no-pager --no-legend; \
      echo; journalctl -u ff-lab-radio-watchdog --no-pager -n 12 -o cat | grep radio-watchdog; \
      echo; printf 'last recovery: '; sudo -n cat /var/lib/ff-lab-radio-watchdog/recovery 2>/dev/null || echo none"
    ;;
  dry-run)
    remote "sudo -n /usr/local/lib/ff-lab/radio-watchdog.sh dry-run"
    ;;
  force)
    printf 'Power-cycles the Zigbee adapter: Zigbee2MQTT is down for about a minute.\n'
    remote "sudo -n /usr/local/lib/ff-lab/radio-watchdog.sh force"
    ;;
  *)
    printf 'FAIL ACTION must be install, status, dry-run or force — not %s\n' "$ACTION" >&2
    exit 2
    ;;
esac
