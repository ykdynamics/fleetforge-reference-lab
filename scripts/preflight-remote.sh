#!/bin/sh
# Read-only gateway preflight — the part that runs ON the gateway.
#
# Piped to the target by scripts/preflight.sh. Kept as its own file, and POSIX sh
# rather than bash, so it can be run directly inside an Ubuntu container to qualify
# the check logic without hardware. Ubuntu's /bin/sh is dash.
#
# It reads. It never installs, starts, stops, configures or deletes anything, and it
# never prints the contents of a credential, token, key or enrollment file.
#
# Inputs (environment):
#   ROLE            zigbee | zwave
#   RADIO_ADAPTER   expected /dev/serial/by-id path, or empty if not yet configured
#   LAB_ROOT        where the lab installs things
#   MQTT_PORT       expected broker port
#   UI_PORT         expected protocol UI port
#
# Output: one "STATUS<TAB>message" line per check. Exit 1 if any FAIL, else 0.

fails=0
warns=0

pass()    { printf 'PASS\t%s\n' "$1"; }
warn()    { printf 'WARN\t%s\n' "$1"; warns=$((warns + 1)); }
fail()    { printf 'FAIL\t%s\n' "$1"; fails=$((fails + 1)); }
unknown() { printf 'UNKNOWN\t%s\n' "$1"; }

ROLE=${ROLE:-}
RADIO_ADAPTER=${RADIO_ADAPTER:-}
LAB_ROOT=${LAB_ROOT:-/opt/fleetforge-lab}
MQTT_PORT=${MQTT_PORT:-1883}
UI_PORT=${UI_PORT:-}

echo '-- host --'

host=$(hostname 2>/dev/null || true)
if [ -n "$host" ]; then pass "hostname: $host"; else warn 'hostname unavailable'; fi

# --- OS baseline ---------------------------------------------------------------
# The lab is qualified for Ubuntu 24.04 LTS Server (arm64) only. Another OS is not
# necessarily broken, but it is not what these procedures were run against, so it is
# a WARN the operator has to weigh rather than a silent PASS.
if [ -r /etc/os-release ]; then
  # shellcheck source=/dev/null
  . /etc/os-release 2>/dev/null || true
  os_desc="${PRETTY_NAME:-${NAME:-unknown}}"
  if [ "${ID:-}" = ubuntu ] && [ "${VERSION_ID:-}" = "24.04" ]; then
    pass "os: $os_desc (the supported baseline)"
  elif [ "${ID:-}" = ubuntu ]; then
    warn "os: $os_desc — the lab is qualified for Ubuntu 24.04 LTS only"
  else
    warn "os: $os_desc — not Ubuntu; the lab is qualified for Ubuntu 24.04 LTS only"
  fi
else
  unknown 'os: /etc/os-release is unreadable'
fi

arch=$(uname -m 2>/dev/null || true)
case "$arch" in
  aarch64) pass "architecture: $arch" ;;
  '')      unknown 'architecture: could not be determined' ;;
  *)       fail "architecture: $arch — the lab's container images are built for arm64 only; use a 64-bit ARM OS on the Pi" ;;
esac

kernel=$(uname -r 2>/dev/null || true)
[ -n "$kernel" ] && pass "kernel: $kernel"

# Raspberry Pi model, where the device tree exposes it. Absent inside a container,
# which is a correct UNKNOWN rather than a failure.
for m in /proc/device-tree/model /sys/firmware/devicetree/base/model; do
  if [ -r "$m" ]; then
    model=$(tr -d '\0' < "$m" 2>/dev/null || true)
    [ -n "$model" ] && pass "model: $model"
    break
  fi
done
[ -n "${model:-}" ] || unknown 'model: no device-tree model (not a Raspberry Pi, or running in a container)'

echo '-- access --'

whoami_out=$(id -un 2>/dev/null || true)
[ -n "$whoami_out" ] && pass "connected as: $whoami_out"

if [ "$(id -u 2>/dev/null || echo 1)" = 0 ]; then
  pass 'privileges: running as root'
elif command -v sudo >/dev/null 2>&1; then
  if sudo -n true >/dev/null 2>&1; then
    pass 'privileges: passwordless sudo available'
  else
    fail 'privileges: sudo requires a password — provisioning needs non-interactive sudo'
  fi
else
  fail 'privileges: sudo is not installed'
fi

echo '-- resources --'

# Disk headroom on the filesystem holding the lab root's parent. Container images and
# radio state live here, and a full root filesystem is how a gateway silently stops
# observing while still looking healthy.
probe=$LAB_ROOT
while [ ! -d "$probe" ] && [ "$probe" != / ]; do probe=$(dirname "$probe"); done
avail_kb=$(df -Pk "$probe" 2>/dev/null | awk 'NR==2 {print $4}')
if [ -n "$avail_kb" ] && [ "$avail_kb" -eq "$avail_kb" ] 2>/dev/null; then
  avail_gb=$((avail_kb / 1024 / 1024))
  if   [ "$avail_kb" -lt 2097152 ]; then fail "disk: ${avail_gb}GB free on $probe — under 2GB, provisioning will not fit"
  elif [ "$avail_kb" -lt 8388608 ]; then warn "disk: ${avail_gb}GB free on $probe — under 8GB, container images and logs will be tight"
  else pass "disk: ${avail_gb}GB free on $probe"
  fi
else
  unknown "disk: free space on $probe could not be determined"
fi

mem_kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)
if [ -n "$mem_kb" ]; then
  mem_mb=$((mem_kb / 1024))
  if [ "$mem_mb" -lt 900 ]; then warn "memory: ${mem_mb}MB total — tight for a broker plus a protocol service"
  else pass "memory: ${mem_mb}MB total"
  fi
else
  unknown 'memory: /proc/meminfo unavailable'
fi

# A read-only root is a real Pi failure mode: the SD card flips to read-only after
# corruption, everything still "runs", and nothing can be written or recovered.
if touchfile=$(mktemp 2>/dev/null); then
  rm -f "$touchfile"
  pass 'filesystem: writable'
else
  fail 'filesystem: could not create a temporary file — the root filesystem may be read-only or full'
fi

echo '-- radio adapter --'

# Stable by-id paths only. The kernel's ttyUSB*/ttyACM* numbering can change across a
# reboot, and a service pointed at the wrong stick fails like a broken mesh.
if [ -d /dev/serial/by-id ]; then
  found=0
  for link in /dev/serial/by-id/*; do
    [ -e "$link" ] || continue
    target=$(readlink -f "$link" 2>/dev/null || echo '?')
    pass "adapter present: $link -> $target"
    found=$((found + 1))
  done
  [ "$found" -eq 0 ] && warn 'no USB serial adapters under /dev/serial/by-id — is the radio stick plugged in?'
else
  warn '/dev/serial/by-id does not exist — no USB serial adapter has been seen on this host'
fi

if [ -n "$RADIO_ADAPTER" ]; then
  if [ -e "$RADIO_ADAPTER" ]; then
    pass "configured adapter resolves: $RADIO_ADAPTER"
  else
    fail "configured adapter is missing: $RADIO_ADAPTER — check the inventory against 'ls -l /dev/serial/by-id/'"
  fi
  case "$RADIO_ADAPTER" in
    /dev/serial/by-id/*) : ;;
    *) warn "configured adapter is not a /dev/serial/by-id path: $RADIO_ADAPTER — kernel numbering can change across reboots" ;;
  esac
else
  unknown 'no radio adapter configured in the inventory for this host yet'
fi

# --- Things that steal USB serial adapters --------------------------------------
# brltty is the Ubuntu-specific one: its udev rules claim several USB-serial bridge
# chips (CH340/CH341 and some CP210x) for braille displays. The dongle then either
# disappears or is held open, and it reads as dead hardware.
if command -v systemctl >/dev/null 2>&1; then
  for svc in brltty brltty-udev ModemManager; do
    state=$(systemctl is-active "$svc" 2>/dev/null || true)
    enabled=$(systemctl is-enabled "$svc" 2>/dev/null || true)
    case "$state" in
      active|activating)
        warn "$svc is $state — it can claim USB serial adapters and make a working radio look dead" ;;
      *)
        case "$enabled" in
          enabled|enabled-runtime)
            warn "$svc is $enabled but not running — it can claim USB serial adapters on the next boot" ;;
          *) pass "$svc is not active" ;;
        esac ;;
    esac
  done
else
  unknown 'systemd not available — cannot check for services that claim USB serial adapters'
fi

if [ -r /usr/lib/udev/rules.d/85-brltty.rules ] || [ -r /lib/udev/rules.d/85-brltty.rules ]; then
  warn 'brltty udev rules are installed — they claim CH340/CP210x adapters used by many Zigbee and Z-Wave sticks'
fi

echo '-- existing installation --'

if command -v docker >/dev/null 2>&1; then
  dv=$(docker --version 2>/dev/null | head -1 || true)
  pass "docker: ${dv:-present}"
  if docker compose version >/dev/null 2>&1; then
    pass "docker compose: $(docker compose version --short 2>/dev/null || echo present)"
  else
    warn 'docker compose plugin not available — provisioning will install it'
  fi
else
  unknown 'docker is not installed — provisioning will install it (this is expected on a fresh host)'
fi

if [ -d "$LAB_ROOT" ]; then
  warn "an existing lab directory is present at $LAB_ROOT — provisioning would ADOPT this host, not set it up fresh"
else
  pass "no existing lab directory at $LAB_ROOT — this is a fresh host"
fi

# Report only the presence and state of the agent. Never its configuration, its token
# or its enrollment identity file contents.
if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q '^ffagent\.service'; then
  agent_state=$(systemctl show ffagent -p ActiveState --value 2>/dev/null || echo unknown)
  warn "a FleetForge agent unit is already installed (state: $agent_state) — this host is already integrated"
else
  pass 'no FleetForge agent unit installed'
fi

if [ -e /var/lib/fleetforge/agent.json ]; then
  warn 'an agent enrollment state file exists — re-running integration must PRESERVE it, not replace it'
fi

echo '-- listeners --'

if command -v ss >/dev/null 2>&1; then
  for p in ${MQTT_PORT:-} ${UI_PORT:-}; do
    [ -n "$p" ] || continue
    if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}\$"; then
      bind=$(ss -ltnH 2>/dev/null | awk '{print $4}' | grep -E "[:.]${p}\$" | head -1)
      case "$bind" in
        0.0.0.0:*|'[::]:'*) warn "port $p is bound on $bind — reachable from the whole network" ;;
        *) pass "port $p is bound on $bind" ;;
      esac
    else
      pass "port $p is free"
    fi
  done
else
  unknown 'ss is not installed — listener checks skipped'
fi

echo '--'
if [ "$fails" -gt 0 ]; then
  printf 'FAIL\t%d failing check(s), %d warning(s) — resolve the failures before provisioning\n' "$fails" "$warns"
  exit 1
fi
printf 'PASS\tpreflight complete: 0 failing check(s), %d warning(s)\n' "$warns"
exit 0
