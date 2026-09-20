#!/usr/bin/env bash
# Operate one gateway's protocol services.
#
#   ACTION=config|up|status|logs|down scripts/stack.sh <host-alias> <role> [inventory]
#
# config  reads   render and validate what would be deployed; contacts no host
# up      mutates deploy the configuration and start the role's services
# status  reads   service state, broker reachability and container health
# logs    reads   tail the role's service logs
# down    mutates stop the role's services, KEEPING all data and pairings
set -euo pipefail

cd "$(dirname "$0")/.."

ACTION=${ACTION:-status}

# shellcheck source=scripts/lib-inventory.sh
lab_usage='make stack-<config|up|status|logs|down> HOST=<alias> ROLE=<zigbee|zwave> [INVENTORY=<path>]'
. scripts/lib-inventory.sh

resolve_gateway "${1:-}" "${2:-}" "${3:-}"

remote() {
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" "$@"
}

compose() {
  remote "cd '$LAB_ROOT/compose' && docker compose --profile '$ROLE' $*"
}

play() {
  ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook \
    -i "$INVENTORY" --limit "$HOST" "$@" ansible/playbooks/gateway-stack.yml
}

printf '== stack %s: %s (role=%s) ==\n' "$ACTION" "$HOST" "$ROLE"

case "$ACTION" in
  config)
    # Renders and validates without touching the host's running services. It does place
    # the configuration, so it is the deploy half of `up` without the start half.
    play -e stack_deploy_only=true
    ;;
  up)
    play
    ;;
  down)
    # Stops services. Deliberately no `-v`: the volumes hold the radio network, the
    # paired devices and the broker's retained registry. Removing them is a separate,
    # explicitly confirmed operation.
    compose down
    printf '\nStopped. Data, pairings and the radio network are untouched.\n'
    ;;
  logs)
    compose "logs --tail=80 --follow"
    ;;
  status)
    printf '\n-- containers --\n'
    compose "ps --format '{{.Service}}\t{{.Status}}'" || {
      printf 'FAIL no stack found at %s on %s\n' "$LAB_ROOT/compose" "$HOST" >&2
      exit 1
    }
    printf '\n-- log bounds actually in effect --\n'
    # Asking Docker what the running container has, not what the Compose file says. The
    # two differ whenever a container predates a configuration change, and that gap is
    # how an unbounded log fills a disk on a host whose config looks correct.
    # Printing the whole LogConfig map avoids quoting a Go-template key through ssh,
    # which is a good way to produce a parse error that looks like a Docker fault.
    remote "docker inspect -f '{{.Name}} {{.HostConfig.LogConfig.Type}} {{.HostConfig.LogConfig.Config}}' \
      \$(docker ps -q --filter name=ff-lab-)"
    printf '\n-- broker --\n'
    # Service health is not device health. This says the broker accepts a connection,
    # nothing about the radio or any device behind it.
    if remote "docker exec ff-lab-mosquitto mosquitto_sub -h 127.0.0.1 -t '\$SYS/broker/version' -C 1 -W 5" 2>/dev/null; then
      printf 'PASS broker answered on the gateway\n'
    else
      printf 'WARN broker did not answer a local subscribe within 5s\n'
    fi
    printf '\n-- disk --\n'
    remote "df -Ph '$LAB_ROOT' | awk 'NR==2 {print \"filesystem \" \$1 \", \" \$4 \" free, \" \$5 \" used\"}'"
    printf '\nNOTE service health is not device health. Nothing above says a radio\n'
    printf '     is working or that any device has been heard from.\n'
    ;;
  *)
    printf 'FAIL ACTION must be config, up, status, logs or down — not %s\n' "$ACTION" >&2
    exit 2
    ;;
esac
