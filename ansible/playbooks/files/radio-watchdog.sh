#!/usr/bin/env bash
# radio-watchdog.sh — keep a Zigbee lab gateway's radio path alive. Runs on the gateway,
# from ff-lab-radio-watchdog.timer. See docs/radio-watchdog.md.
#
#   radio-watchdog.sh [check|dry-run|force]
#
# check    (the timer) act only on what it finds
# dry-run  report what check would do, change nothing
# force    power-cycle the adapter now, whatever the traffic (a hardware test)
#
# Two failures this exists for, both seen on the lab's Zigbee gateway (2026-10-23..28):
#  1. The adapter drops off USB and comes back seconds later. Docker restarts the
#     container while the device node is still missing, fails ("error gathering device
#     information") and never tries again, so Zigbee2MQTT stays down.
#  2. The coordinator keeps its USB link but stops passing radio traffic. Zigbee2MQTT
#     reports itself online and hears nothing. Restarting the container does not clear
#     it; cutting the adapter's power does.
#
# Silence is judged by fresh (non-retained) device messages, so it needs a device that
# reports on its own: the lab's mains-powered plug publishes every 10 seconds. A gateway
# with only sleepy battery sensors would look silent and must not run this.
set -uo pipefail

ENV_FILE=${RADIO_WATCHDOG_ENV:-/etc/ff-lab/radio-watchdog.env}
# shellcheck disable=SC1090
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

ADAPTER=${ADAPTER:?ADAPTER (the /dev/serial/by-id path) is not set}
CONTAINER=${CONTAINER:-ff-lab-zigbee2mqtt}
BROKER=${BROKER:-ff-lab-mosquitto}
TOPIC=${TOPIC:-zigbee2mqtt/+}
SILENCE_S=${SILENCE_S:-300}
COOLDOWN_S=${COOLDOWN_S:-3600}
USB_HUBS=${USB_HUBS:-1-1 2}
POWER_OFF_S=${POWER_OFF_S:-5}
REBOOT=${REBOOT:-0}
REBOOT_COOLDOWN_S=${REBOOT_COOLDOWN_S:-43200}
STATE_DIR=${STATE_DIR:-/var/lib/ff-lab-radio-watchdog}
DOCKER=${DOCKER:-docker}
UHUBCTL=${UHUBCTL:-uhubctl}
SYSTEMCTL=${SYSTEMCTL:-systemctl}
SLEEP=${SLEEP:-sleep}

MODE=${1:-check}
case "$MODE" in check|dry-run|force) ;; *) echo "usage: $0 [check|dry-run|force]" >&2; exit 2 ;; esac

log() { printf 'radio-watchdog: %s\n' "$*"; }
now() { date +%s; }
mkdir -p "$STATE_DIR"

# state files hold "<epoch> <action>" for the last recovery and the last reboot
read_state() { [ -s "$STATE_DIR/$1" ] && cat "$STATE_DIR/$1" || echo "0 none"; }
write_state() { [ "$MODE" = dry-run ] || echo "$(now) $2" > "$STATE_DIR/$1"; }

act() { # act <description> <command...>: run it (output discarded) unless this is a dry run
  local what="$1"; shift
  if [ "$MODE" = dry-run ]; then log "would $what"; return 0; fi
  log "$what"; "$@" >/dev/null
}

wait_for_adapter() {
  local _
  for _ in $(seq 30); do [ -e "$ADAPTER" ] && return 0; "$SLEEP" 1; done
  return 1
}

power_cycle() {
  act "stop $CONTAINER" "$DOCKER" stop "$CONTAINER"
  if command -v "$UHUBCTL" >/dev/null 2>&1; then
    # A Raspberry Pi 4's ports are ganged: power only drops with both hubs off.
    local hub
    for hub in $USB_HUBS; do act "cut USB power on hub $hub" "$UHUBCTL" -l "$hub" -a 0; done
    act "wait ${POWER_OFF_S}s unpowered" "$SLEEP" "$POWER_OFF_S"
    for hub in $USB_HUBS; do act "restore USB power on hub $hub" "$UHUBCTL" -l "$hub" -a 1; done
  else
    log "uhubctl is not installed: restarting the container only (does not clear a hung coordinator)"
  fi
  if [ "$MODE" != dry-run ] && ! wait_for_adapter; then
    log "the adapter did not come back within 30s; leaving $CONTAINER stopped"
    write_state recovery usb-cycle-no-adapter
    return 1
  fi
  act "start $CONTAINER" "$DOCKER" start "$CONTAINER"
  write_state recovery usb-cycle
}

if [ ! -e "$ADAPTER" ]; then
  log "adapter $ADAPTER is absent; nothing to do until the kernel re-enumerates it"
  exit 0
fi

if [ "$MODE" = force ]; then
  power_cycle; exit $?
fi

read -r running exit_code < <("$DOCKER" inspect -f '{{.State.Running}} {{.State.ExitCode}}' "$CONTAINER" 2>/dev/null || echo missing -)
if [ "$running" = missing ]; then
  log "container $CONTAINER does not exist; not this watchdog's job (run make stack-up)"
  exit 0
fi
if [ "$running" != true ]; then
  # A deliberate stop (docker compose stop: radio-backup, radio-adapter-reset, reset)
  # ends with exit 0 and is left alone. Losing the adapter ends with exit 2.
  if [ "$exit_code" = 0 ]; then
    log "$CONTAINER was stopped cleanly (exit 0): a deliberate stop, left alone"
    exit 0
  fi
  act "start $CONTAINER (exited $exit_code while its adapter is present)" "$DOCKER" start "$CONTAINER"
  write_state recovery start
  exit 0
fi

# Silence can only be judged through a running broker; a stopped one (a backup, a reset)
# says nothing about the radio.
if [ "$("$DOCKER" inspect -f '{{.State.Running}}' "$BROKER" 2>/dev/null)" != true ]; then
  log "broker $BROKER is not running; radio silence cannot be judged, nothing done"
  exit 0
fi

# -R drops retained messages, so only traffic the radio produced during this wait counts.
if "$DOCKER" exec "$BROKER" mosquitto_sub -R -t "$TOPIC" -C 1 -W "$SILENCE_S" >/dev/null 2>&1; then
  [ "$MODE" = dry-run ] || rm -f "$STATE_DIR/recovery"
  log "healthy: device traffic within ${SILENCE_S}s"
  exit 0
fi

read -r last_at last_action < <(read_state recovery)
age=$(( $(now) - last_at ))
if [ "$age" -ge "$COOLDOWN_S" ]; then
  log "no device message for ${SILENCE_S}s: power-cycling the adapter"
  power_cycle; exit $?
fi

# Still silent within the cool-down: the last recovery did not help.
read -r reboot_at _ < <(read_state reboot)
if [ "$REBOOT" = 1 ] && [ "$last_action" = usb-cycle ] && [ $(( $(now) - reboot_at )) -ge "$REBOOT_COOLDOWN_S" ]; then
  log "still silent ${age}s after a USB power cycle: rebooting the gateway"
  write_state reboot reboot
  act "reboot" "$SYSTEMCTL" reboot
  exit 0
fi
log "still silent; last recovery ($last_action) ${age}s ago, next allowed in $(( COOLDOWN_S - age ))s"
exit 1
