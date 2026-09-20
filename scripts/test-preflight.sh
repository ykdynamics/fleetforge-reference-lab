#!/usr/bin/env bash
# Exercise the gateway preflight's check logic and its failure paths.
#
# The remote half runs inside an Ubuntu 24.04 container, so the checks are exercised
# against real Ubuntu userland without a gateway. That makes this SIMULATED evidence,
# not hardware qualification: a container has no device tree, no systemd and no USB,
# so the checks that depend on those correctly report UNKNOWN here and can only be
# confirmed on a real Pi.
#
# Usage: scripts/test-preflight.sh        (needs docker; arm64 and amd64 images)
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE=${IMAGE:-ubuntu:24.04}
REMOTE=$PWD/scripts/preflight-remote.sh
EXAMPLE=inventory/inventory.example.yml
passed=0
failed=0

# run_case <name> <platform> <setup-shell> <expected-exit> <grep-pattern...>
run_case() {
  local name=$1 platform=$2 setup=$3 want_exit=$4; shift 4
  local out status
  set +e
  out=$(docker run --rm --platform "$platform" \
        -v "$REMOTE:/pf.sh:ro" -e ROLE="${CASE_ROLE:-zigbee}" \
        -e RADIO_ADAPTER="${CASE_ADAPTER:-}" -e LAB_ROOT=/opt/fleetforge-lab \
        -e MQTT_PORT=1883 -e UI_PORT=8099 \
        "$IMAGE" sh -c "$setup ${CASE_RUNNER:-sh /pf.sh}" 2>&1)
  status=$?
  set -e

  local ok=1
  [ "$status" = "$want_exit" ] || { ok=0; printf '  expected exit %s, got %s\n' "$want_exit" "$status"; }
  local pattern
  for pattern in "$@"; do
    grep -qE "$pattern" <<<"$out" || { ok=0; printf '  missing expected line: %s\n' "$pattern"; }
  done

  if [ "$ok" = 1 ]; then
    printf 'PASS  %s\n' "$name"; passed=$((passed + 1))
  else
    printf 'FAIL  %s\n' "$name"; failed=$((failed + 1))
    printf '%s\n' "$out" | sed 's/^/      | /'
  fi
}

command -v docker >/dev/null 2>&1 || { echo 'FAIL docker is required to exercise the preflight checks'; exit 1; }
docker image inspect "$IMAGE" >/dev/null 2>&1 || docker pull -q "$IMAGE" >/dev/null

echo '== remote checks, against Ubuntu 24.04 userland (simulated, not hardware) =='

run_case 'clean host passes' linux/arm64 '' 0 \
  '^PASS.*os: Ubuntu 24\.04.*supported baseline' \
  '^PASS.*architecture: aarch64' \
  '^PASS.*no existing lab directory' \
  '^PASS.*preflight complete: 0 failing'

run_case 'wrong architecture fails' linux/amd64 '' 1 \
  '^FAIL.*architecture: x86_64' \
  '^FAIL.*1 failing check'

CASE_ADAPTER=/dev/serial/by-id/usb-NOT-PRESENT-if00 \
run_case 'configured adapter missing fails' linux/arm64 '' 1 \
  '^FAIL.*configured adapter is missing'

CASE_ADAPTER=/dev/ttyACM0 \
run_case 'unstable adapter path warns' linux/arm64 'touch /dev/ttyACM0;' 0 \
  '^WARN.*not a /dev/serial/by-id path'

run_case 'existing install reports adoption' linux/arm64 \
  'mkdir -p /opt/fleetforge-lab /var/lib/fleetforge && echo "{}" > /var/lib/fleetforge/agent.json;' 0 \
  '^WARN.*would ADOPT this host' \
  '^WARN.*enrollment state file exists'

run_case 'brltty udev rules warn' linux/arm64 \
  'mkdir -p /usr/lib/udev/rules.d && touch /usr/lib/udev/rules.d/85-brltty.rules;' 0 \
  '^WARN.*brltty udev rules'

CASE_RUNNER='su labops -c "sh /pf.sh"' \
run_case 'sudo requiring a password fails' linux/arm64 \
  'apt-get -qq update >/dev/null 2>&1; apt-get -qq install -y sudo >/dev/null 2>&1; useradd -m labops;' 1 \
  '^FAIL.*sudo requires a password'

echo
echo '== local driver: usage and inventory resolution (no host contacted) =='

# usage_case <name> <expected-exit> <pattern> -- <args...>
usage_case() {
  local name=$1 want_exit=$2 pattern=$3; shift 4
  local out status
  set +e
  out=$(./scripts/preflight.sh "$@" 2>&1); status=$?
  set -e
  if [ "$status" = "$want_exit" ] && grep -qE "$pattern" <<<"$out"; then
    printf 'PASS  %s\n' "$name"; passed=$((passed + 1))
  else
    printf 'FAIL  %s (exit %s, wanted %s)\n' "$name" "$status" "$want_exit"; failed=$((failed + 1))
    printf '%s\n' "$out" | sed 's/^/      | /'
  fi
}

usage_case 'missing HOST is a usage error'   2 'HOST= is required'                    -- '' ''
usage_case 'missing ROLE is a usage error'   2 'ROLE= is required'                    -- 'lab-gw-zigbee' ''
usage_case 'invalid ROLE is a usage error'   2 "ROLE must be 'zigbee' or 'zwave'"     -- 'lab-gw-zigbee' 'bogus'
usage_case 'unknown host is a usage error'   2 'is not in'                            -- 'nope' 'zigbee' "$EXAMPLE"
usage_case 'role/inventory mismatch refused' 2 'but the inventory says'               -- 'lab-gw-zigbee' 'zwave' "$EXAMPLE"

echo
if [ "$failed" -gt 0 ]; then
  printf 'FAIL %d of %d preflight scenarios failed\n' "$failed" "$((passed + failed))"
  exit 1
fi
printf 'PASS all %d preflight scenarios (simulated — not hardware qualification)\n' "$passed"
