#!/usr/bin/env bash
# Provision one lab gateway, or show what provisioning would change.
#
#   scripts/provision.sh <host-alias> <role> [inventory-path]     # applies changes
#   MODE=plan scripts/provision.sh <host-alias> <role> [path]     # read-only diff
#
# Exit codes (see docs/command-contract.md):
#   0  applied (or planned) successfully
#   1  a task failed, or the host could not be reached
#   2  usage error — nothing was attempted
set -euo pipefail

cd "$(dirname "$0")/.."

MODE=${MODE:-apply}

# shellcheck source=scripts/lib-inventory.sh
lab_usage='make provision|provision-plan HOST=<alias> ROLE=<zigbee|zwave> [INVENTORY=<path>]'
. scripts/lib-inventory.sh

resolve_gateway "${1:-}" "${2:-}" "${3:-}"

command -v ansible-playbook >/dev/null 2>&1 || {
  printf 'FAIL ansible-playbook is required (Ansible is a documented prerequisite)\n' >&2
  exit 1
}

case "$MODE" in
  plan)  verb='plan (read-only)'; extra=(--check --diff) ;;
  apply) verb='apply';            extra=() ;;
  *) printf 'FAIL MODE must be plan or apply, not %s\n' "$MODE" >&2; exit 2 ;;
esac

printf '== provision %s (role=%s) — %s ==\n' "$HOST" "$ROLE" "$verb"
printf 'inventory: %s\n' "$INVENTORY"
printf 'target:    %s\n\n' "$TARGET"

if [ "$MODE" = apply ]; then
  # One named host, every time. There is no "all hosts" form of this command, so a
  # mistyped alias cannot become an estate-wide change.
  printf 'This CHANGES %s: masks ModemManager and brltty, installs Docker,\n' "$HOST"
  printf 'creates lab directories. It does not touch networking, radio data or\n'
  printf 'an existing stack.\n\n'
fi

# ANSIBLE_CONFIG so the lab's settings apply wherever this is run from.
ANSIBLE_CONFIG=ansible/ansible.cfg \
exec ansible-playbook \
  -i "$INVENTORY" \
  --limit "$HOST" \
  "${extra[@]}" \
  ansible/playbooks/gateway-base.yml
