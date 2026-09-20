#!/usr/bin/env bash
# Verify that every *.example.yml in this repository parses as YAML, and that no
# example file carries an obvious real secret.
#
# Read-only. Fails closed: if no YAML parser is available, that is FAIL, not a skip --
# an unverified example is not a verified one.
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v python3 >/dev/null 2>&1; then
  echo 'FAIL python3 is required to validate the example files'
  exit 1
fi

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
  echo 'FAIL PyYAML is required to validate the example files (pip install pyyaml)'
  exit 1
fi

# Portable collection: `mapfile` does not exist in the bash 3.2 that ships on macOS.
files=()
while IFS= read -r f; do
  files+=("$f")
done < <(find . -name '*.example.yml' -not -path './.git/*' | sort)

if [ "${#files[@]}" -eq 0 ]; then
  echo 'FAIL no *.example.yml files found — the example inventory is missing'
  exit 1
fi

for f in "${files[@]}"; do
  if ! python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$f"; then
    printf 'FAIL %s does not parse as YAML\n' "$f"
    exit 1
  fi
  printf 'PASS %s parses as YAML\n' "$f"
done

# Example files reference secrets by path and must never contain a value. This catches
# the obvious accidents; it is a safety net, not a substitute for reading the diff.
if grep -nE '(BEGIN [A-Z ]*PRIVATE KEY|^[[:space:]]*(api_key|password|token|secret)[[:space:]]*:[[:space:]]*[^ #]+)' "${files[@]}"; then
  echo 'FAIL an example file appears to contain a secret value rather than a file path'
  exit 1
fi

printf 'PASS %d example file(s) validated\n' "${#files[@]}"
