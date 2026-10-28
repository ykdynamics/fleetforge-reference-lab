#!/usr/bin/env bash
# Exercise the radio watchdog's decisions against fake docker/uhubctl/systemctl.
#
# SIMULATED evidence: it proves which action each situation leads to, not that a USB
# power cycle clears a hung coordinator. That part is checked on the gateway itself
# with `make radio-watchdog-force` (docs/radio-watchdog.md).
set -euo pipefail

cd "$(dirname "$0")/.."
WATCHDOG=ansible/playbooks/files/radio-watchdog.sh
passed=0
failed=0
ok()  { printf 'PASS  %s\n' "$1"; passed=$((passed + 1)); }
bad() { printf 'FAIL  %s\n' "$1"; failed=$((failed + 1)); shift; printf '%s\n' "$@" | sed 's/^/      | /'; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"

# docker: FAKE_RUNNING=true|false|missing for inspect; FAKE_TRAFFIC=1 makes mosquitto_sub see a message
cat > "$T/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "$CALLS"
case "$1" in
  inspect) last="${*: -1}"
           if [ "$last" = ff-lab-mosquitto ]; then echo "${FAKE_BROKER:-true}"; exit 0; fi
           [ "$FAKE_RUNNING" = missing ] && exit 1; echo "$FAKE_RUNNING ${FAKE_EXIT:-0}" ;;
  exec) [ "${FAKE_TRAFFIC:-0}" = 1 ] && { echo 'zigbee2mqtt/plug {}'; exit 0; }; exit 27 ;;
  *) exit 0 ;;
esac
EOF
printf '#!/usr/bin/env bash\necho "uhubctl $*" >> "$CALLS"\n' > "$T/bin/uhubctl"
printf '#!/usr/bin/env bash\necho "systemctl $*" >> "$CALLS"\n' > "$T/bin/systemctl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/sleep"
chmod +x "$T/bin/"*

run() { # run <mode> [VAR=value ...]: fresh call log, shared state dir
  local mode="$1"; shift
  : > "$T/calls"
  env -i PATH="$T/bin:/usr/bin:/bin" CALLS="$T/calls" RADIO_WATCHDOG_ENV=/nonexistent \
    ADAPTER="$T/adapter" STATE_DIR="$T/state" DOCKER="$T/bin/docker" UHUBCTL="$T/bin/uhubctl" \
    SYSTEMCTL="$T/bin/systemctl" SLEEP="$T/bin/sleep" FAKE_RUNNING=true FAKE_TRAFFIC=0 "$@" \
    bash "$WATCHDOG" "$mode" 2>&1 || true   # a still-silent check exits 1 on purpose
}
calls() { cat "$T/calls"; }
expect() { # expect <name> <grep -E pattern in calls> [absent]
  if [ "${3:-}" = absent ]; then
    if grep -qE "$2" "$T/calls"; then bad "$1" "$(calls)"; else ok "$1"; fi
  else
    if grep -qE "$2" "$T/calls"; then ok "$1"; else bad "$1" "$(calls)"; fi
  fi
}

echo '== radio watchdog decisions (fake tools, no gateway contacted) =='

rm -f "$T/adapter"
out=$(run check)
grep -q 'is absent' <<<"$out" && ok 'adapter absent: reports and waits' || bad 'adapter absent: reports and waits' "$out"
expect 'adapter absent: no docker or USB action' 'start|stop|uhubctl' absent

touch "$T/adapter"
run check FAKE_RUNNING=false FAKE_EXIT=2 >/dev/null
expect 'container exited 2 (adapter lost) with adapter present: docker start' '^docker start ff-lab-zigbee2mqtt$'
expect 'container exited 2: no USB power cycle' 'uhubctl' absent

out=$(run check FAKE_RUNNING=false FAKE_EXIT=0)
expect 'container stopped cleanly (exit 0, a deliberate stop): left alone' 'start|uhubctl' absent
grep -q 'deliberate stop' <<<"$out" && ok 'clean stop: says why it is left alone' || bad 'clean stop: says why it is left alone' "$out"

out=$(run check FAKE_RUNNING=missing)
expect 'container missing: no action' 'start|stop|uhubctl' absent

rm -rf "$T/state"
out=$(run check FAKE_BROKER=false)
expect 'broker stopped: silence not judged, no power cycle' 'mosquitto_sub|stop|uhubctl' absent
grep -q 'cannot be judged' <<<"$out" && ok 'broker stopped: says so' || bad 'broker stopped: says so' "$out"

rm -rf "$T/state"
out=$(run check FAKE_TRAFFIC=1)
grep -q healthy <<<"$out" && ok 'device traffic: healthy' || bad 'device traffic: healthy' "$out"
expect 'healthy: no stop, start or USB action' 'stop|start|uhubctl' absent
expect 'healthy: waits only for non-retained messages' 'mosquitto_sub -R -t zigbee2mqtt/\+ -C 1 -W 300'

rm -rf "$T/state"
run check >/dev/null
expect 'silent: stops Zigbee2MQTT first' '^docker stop ff-lab-zigbee2mqtt$'
expect 'silent: cuts power on hub 1-1' '^uhubctl -l 1-1 -a 0$'
expect 'silent: cuts power on hub 2 (Pi 4 gangs both)' '^uhubctl -l 2 -a 0$'
expect 'silent: restores power' '^uhubctl -l 1-1 -a 1$'
expect 'silent: starts Zigbee2MQTT again' '^docker start ff-lab-zigbee2mqtt$'
grep -q ' usb-cycle$' "$T/state/recovery" && ok 'silent: records the recovery' || bad 'silent: records the recovery' "$(cat "$T/state/recovery" 2>&1)"

out=$(run check)
expect 'still silent inside the cool-down: no second power cycle' 'uhubctl|stop' absent
grep -q 'next allowed in' <<<"$out" && ok 'cool-down: says when' || bad 'cool-down: says when' "$out"
expect 'cool-down, reboot not enabled: no reboot' 'systemctl reboot' absent

run check REBOOT=1 >/dev/null
expect 'still silent after a power cycle, REBOOT=1: reboots' '^systemctl reboot$'
run check REBOOT=1 >/dev/null
expect 'reboot cool-down: no second reboot' 'systemctl reboot' absent

rm -rf "$T/state"
out=$(run dry-run)
expect 'dry-run: changes nothing' 'stop|start|uhubctl|reboot' absent
grep -q 'would cut USB power' <<<"$out" && ok 'dry-run: reports the power cycle it would do' || bad 'dry-run: reports the power cycle it would do' "$out"
[ ! -e "$T/state/recovery" ] && ok 'dry-run: records no recovery' || bad 'dry-run: records no recovery' "$(cat "$T/state/recovery")"

run force FAKE_TRAFFIC=1 >/dev/null
expect 'force: power-cycles even with traffic' '^uhubctl -l 1-1 -a 0$'

rm -rf "$T/state"
out=$(run check UHUBCTL=/nonexistent/uhubctl)
grep -q 'uhubctl is not installed' <<<"$out" && ok 'without uhubctl: says it can only restart' || bad 'without uhubctl: says it can only restart' "$out"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
