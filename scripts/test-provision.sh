#!/usr/bin/env bash
# Exercise the provisioning playbook's guards and the driver's usage handling.
#
# Runs against a local-connection fixture, so no gateway is contacted and nothing is
# installed anywhere. That makes this SIMULATED evidence: it proves the playbook refuses
# what it should refuse, not that provisioning works on a Pi.
set -euo pipefail

cd "$(dirname "$0")/.."

FIXTURE=ansible/tests/two-hosts.yml
PLAYBOOK=ansible/playbooks/gateway-base.yml
EXAMPLE=inventory/inventory.example.yml
passed=0
failed=0

command -v ansible-playbook >/dev/null 2>&1 || { echo 'FAIL ansible-playbook is required'; exit 1; }

ok()   { printf 'PASS  %s\n' "$1"; passed=$((passed + 1)); }
bad()  { printf 'FAIL  %s\n' "$1"; failed=$((failed + 1)); shift; printf '%s\n' "$@" | sed 's/^/      | /'; }

echo '== playbook guards (local fixture, no gateway contacted) =='

# Selecting more than one host must be refused before anything is evaluated.
out=$(ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook -i "$FIXTURE" --check "$PLAYBOOK" 2>&1 || true)
if grep -q 'provisions one named host at a time' <<<"$out"; then
  ok 'refuses to provision more than one host at a time'
else
  bad 'refuses to provision more than one host at a time' "$out"
fi

# A single host must get past that guard. The architecture assertion then fails here,
# because the fixture runs against this machine rather than an arm64 Pi -- which is the
# baseline check failing closed, and is the expected result.
out=$(ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook -i "$FIXTURE" --limit fake-gw-a --check "$PLAYBOOK" 2>&1 || true)
if grep -q 'provisions one named host at a time' <<<"$out"; then
  bad 'a single --limit host passes the host-count guard' "$out"
elif grep -q 'container images are' <<<"$out"; then
  ok 'a single --limit host passes the host-count guard'
  ok 'a non-arm64 host is refused by the architecture assertion'
else
  bad 'a single --limit host passes the host-count guard' "$out"
fi

echo
echo '== driver usage (nothing attempted) =='

usage_case() {
  local name=$1 want=$2 pattern=$3; shift 3
  local out status
  set +e
  out=$(MODE=plan ./scripts/provision.sh "$@" 2>&1); status=$?
  set -e
  if [ "$status" = "$want" ] && grep -qE "$pattern" <<<"$out"; then
    ok "$name"
  else
    bad "$name (exit $status, wanted $want)" "$out"
  fi
}

usage_case 'missing HOST is a usage error'   2 'HOST= is required'                '' ''
usage_case 'missing ROLE is a usage error'   2 'ROLE= is required'                'lab-gw-zigbee' ''
usage_case 'invalid ROLE is a usage error'   2 "ROLE must be 'zigbee' or 'zwave'" 'lab-gw-zigbee' 'nope'
usage_case 'unknown host is a usage error'   2 'is not in'                        'nope' 'zigbee' "$EXAMPLE"
usage_case 'role/inventory mismatch refused' 2 'but the inventory says'           'lab-gw-zigbee' 'zwave' "$EXAMPLE"

# MODE is the plan/apply switch; anything else must not quietly become one of them.
set +e
out=$(MODE=bogus ./scripts/provision.sh lab-gw-zigbee zigbee "$EXAMPLE" 2>&1); status=$?
set -e
if [ "$status" = 2 ] && grep -q 'MODE must be plan or apply' <<<"$out"; then
  ok 'an unrecognised MODE is refused'
else
  bad "an unrecognised MODE is refused (exit $status)" "$out"
fi

echo
if [ "$failed" -gt 0 ]; then
  printf 'FAIL %d of %d provisioning scenarios failed\n' "$failed" "$((passed + failed))"
  exit 1
fi
printf 'PASS all %d provisioning scenarios (simulated — no gateway was contacted)\n' "$passed"
