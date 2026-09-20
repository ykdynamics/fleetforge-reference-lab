#!/usr/bin/env bash
# Archive a gateway's protocol state to private storage, with a checksum manifest.
#
#   scripts/radio-backup.sh <host-alias> <role> <backup-dir> [inventory]
#   DRY_RUN=1 ...   report what would be archived and change nothing
#   STOP_SERVICES=1 stop the radio stack for a consistent archive, then start it again
#
# What this protects: the radio network. The Zigbee network key and paired device list,
# or the Z-Wave controller's node database. Losing them means physically re-pairing every
# device, one at a time, by hand.
#
# What it deliberately leaves alone: the FleetForge agent's enrolment identity. That has a
# different lifecycle and a different owner, and sweeping it into a radio backup invites
# restoring a gateway's identity from a stale archive and minting a confusing duplicate.
set -euo pipefail

cd "$(dirname "$0")/.."

# shellcheck source=scripts/lib-inventory.sh
lab_usage='make radio-backup HOST=<alias> ROLE=<zigbee|zwave> BACKUP_DIR=<private path> [DRY_RUN=1] [STOP_SERVICES=1]'
. scripts/lib-inventory.sh

resolve_gateway "${1:-}" "${2:-}" "${4:-}"
BACKUP_DIR=${3:-}
DRY_RUN=${DRY_RUN:-}
STOP_SERVICES=${STOP_SERVICES:-}

[ -n "$BACKUP_DIR" ] || die_usage 'BACKUP_DIR= is required — an absolute path OUTSIDE this repository'
case "$BACKUP_DIR" in
  /*) ;;
  *) die_usage "BACKUP_DIR must be an absolute path, not '$BACKUP_DIR'" ;;
esac

case "$ROLE" in
  zigbee) service=zigbee2mqtt ;;
  zwave)  service=zwave-js-ui ;;
esac
data_dir="$LAB_ROOT/data/$service"

remote() { ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" "$@"; }

printf '== radio backup: %s (role=%s) ==\n' "$HOST" "$ROLE"
printf 'source:  %s\n' "$data_dir"
printf 'archive: %s\n\n' "$BACKUP_DIR"

if ! remote "sudo test -d '$data_dir'"; then
  printf 'FAIL no protocol data at %s on %s\n' "$data_dir" "$HOST" >&2
  exit 1
fi

# Sizes and file count only. Never the contents: this directory holds the network key.
printf -- '-- what would be archived --\n'
remote "sudo du -sh '$data_dir' 2>/dev/null; sudo find '$data_dir' -type f | wc -l | sed 's/^/files: /'"

if [ -n "$DRY_RUN" ]; then
  cat <<EOF

DRY RUN — nothing was read, written or stopped.

Re-run without DRY_RUN=1 to archive. Consider STOP_SERVICES=1: a running service can be
mid-write, and an archive taken underneath it may restore to a state the service never
actually had.
EOF
  exit 0
fi

mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
archive="$BACKUP_DIR/${HOST}-${ROLE}-${stamp}.tar.gz"

if [ -n "$STOP_SERVICES" ]; then
  printf '\n-- stopping the radio stack for a consistent archive --\n'
  remote "cd '$LAB_ROOT/compose' && docker compose --profile '$ROLE' stop $service"
fi

printf '\n-- archiving --\n'
# Streamed over ssh and written locally: the archive never lands on the gateway, where a
# later disk-space problem is exactly when you would need it elsewhere.
if ! remote "sudo tar -C '$LAB_ROOT/data' -czf - '$service'" > "$archive"; then
  rm -f "$archive"
  [ -n "$STOP_SERVICES" ] && remote "cd '$LAB_ROOT/compose' && docker compose --profile '$ROLE' start $service" || true
  printf 'FAIL the archive could not be created\n' >&2
  exit 1
fi
chmod 600 "$archive"

if [ -n "$STOP_SERVICES" ]; then
  printf -- '-- starting the radio stack again --\n'
  remote "cd '$LAB_ROOT/compose' && docker compose --profile '$ROLE' start $service"
fi

# A checksum is only worth having if it was verified after writing, so verify it here
# rather than recording a number nobody ever checks.
if command -v shasum >/dev/null 2>&1; then
  sha=$(shasum -a 256 "$archive" | awk '{print $1}')
elif command -v sha256sum >/dev/null 2>&1; then
  sha=$(sha256sum "$archive" | awk '{print $1}')
else
  printf 'FAIL no sha256 tool available to produce a manifest\n' >&2
  exit 1
fi

manifest="${archive}.sha256"
printf '%s  %s\n' "$sha" "$(basename "$archive")" > "$manifest"
chmod 600 "$manifest"

printf -- '\n-- verifying --\n'
if tar -tzf "$archive" >/dev/null 2>&1; then
  printf 'PASS archive is readable (%s entries)\n' "$(tar -tzf "$archive" | wc -l | tr -d ' ')"
else
  printf 'FAIL archive is not readable — treat this backup as failed\n' >&2
  exit 1
fi
if (cd "$BACKUP_DIR" && if command -v shasum >/dev/null 2>&1; then
      shasum -a 256 -c "$(basename "$manifest")"
    else
      sha256sum -c "$(basename "$manifest")"
    fi) >/dev/null 2>&1; then
  printf 'PASS checksum verified after writing\n'
else
  printf 'FAIL checksum did not verify — treat this backup as failed\n' >&2
  exit 1
fi

cat <<EOF

archive   $archive
manifest  $manifest
sha256    $sha

What this restores, and what it does not. It restores the protocol service's stored
state. It is NOT a universal promise that the radio network comes back: some adapters
hold network identity in the adapter itself, so restoring the service's files onto a
different or re-flashed stick may not reconstitute the mesh. Plan to re-pair, and treat a
successful restore as a bonus rather than the plan.

The FleetForge agent's enrolment identity is NOT in this archive, on purpose.
EOF
