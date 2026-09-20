# Imaging a gateway Pi

This lab **starts from a Raspberry Pi that is already booted and reachable over SSH.**
Getting to that point is standard work, it has nothing to do with FleetForge, and it is
documented here separately so the walkthrough does not have to repeat it.

Everything on this page is runnable today. It needs nothing from this repository.

## The baseline

**Ubuntu Server 24.04 LTS, 64-bit (arm64), on a Raspberry Pi 4 Model B.**

- **Ubuntu Server 24.04 LTS**, because it is the OS this lab is being qualified against,
  and its five-year support window suits something meant to be rebuilt from these
  instructions years from now.
- **Server, not Desktop** — a gateway has no display. A desktop image adds attack surface
  and disk usage for nothing.
- **64-bit ARM**, because the container images this lab runs are published for `arm64`.

Raspberry Pi OS Lite 64-bit is a close relative and most of this lab would work on it, but
it is **not** what these procedures are being run against. Mixing the two is how you
inherit a difference — `netplan` versus `dhcpcd`, `cloud-init` versus Imager-configured
users — at the point where something is already failing. Pick the baseline.

The exact release in use is recorded in
[Hardware and versions](hardware-and-versions.md).

## Write the image

Raspberry Pi Imager can write it: choose *Other general-purpose OS* → *Ubuntu* →
**Ubuntu Server 24.04 LTS (64-bit)**. Canonical's own images work equally well.

Before writing, open the **OS customisation** settings and set:

| Setting | Why |
|---|---|
| Hostname | A distinct name per gateway. The lab addresses hosts by inventory alias, so pick something you will recognise |
| Username and password | This account will hold sudo. Ubuntu's stock `ubuntu` user forces a password change on first login, which a non-interactive tool cannot answer — set your own |
| **Enable SSH → public-key only** | Password SSH on a device that runs your radio network is not worth the convenience |
| Wi-Fi (if not using Ethernet) | Ethernet is steadier, but either works. This lab makes no network demands |
| Locale and timezone | The timezone matters: your logs and your lamp observations need to agree |

Write the card, put it in the Pi, and power it on.

**First boot takes a while.** Ubuntu Server runs `cloud-init` on first boot to apply that
customisation, and SSH may refuse connections for a minute or two after the Pi appears on
the network. That is normal; wait rather than re-imaging.

## Confirm you can reach it

```sh
ssh <user>@<your-pi-hostname>
```

From the Pi, confirm the facts the lab depends on:

```sh
uname -m          # expect: aarch64
sudo -n true && echo "sudo ok"
cloud-init status # expect: status: done
```

If `uname -m` does not say `aarch64`, a 32-bit image was written and the container images
will not run. Re-image before going further.

If `sudo -n true` fails, sudo is asking for a password. Provisioning is non-interactive
and cannot answer a prompt, so fix this now — it is the single most common reason the
first real lab command fails.

If `cloud-init status` still reports `running`, first boot has not finished. Wait for it.
Provisioning a host mid-`cloud-init` races against it.

## Update, then plug in the radio

```sh
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

After it comes back, plug the USB radio adapter in — one per gateway — and find its stable
path:

```sh
ls -l /dev/serial/by-id/
```

You should see a symlink named after the adapter, pointing at a `ttyUSB*` or `ttyACM*`
node. **Record the full `/dev/serial/by-id/...` path.** It goes into your inventory, and
it is the path the lab uses everywhere — see
[Hardware and versions § Always use a stable adapter path](hardware-and-versions.md#always-use-a-stable-adapter-path).

If the directory does not exist or is empty, the adapter is not enumerating. Try a
different USB port or cable before suspecting the adapter; underpowered or data-less USB
cables are a common cause.

## Two services that steal USB serial adapters

Both are present on Ubuntu and both make a working radio look like dead hardware.

**`brltty`** drives braille displays, and its udev rules claim several USB-serial bridge
chips — CH340/CH341 and some CP210x — which are exactly the chips many Zigbee and Z-Wave
sticks use. When it grabs your adapter, the device node disappears or is held open.

**`ModemManager`** opens USB serial devices looking for a modem, with the same result.

Host provisioning (WP-02) handles both. They are named here so that a dead-looking adapter
on a fresh Ubuntu host is not mistaken for a hardware fault — and
`make preflight` reports on both before you get that far.

## You are ready when

- The Pi boots and you can SSH in with a key
- `uname -m` reports `aarch64`
- `cloud-init status` reports `done`
- `sudo -n true` succeeds without a password prompt
- `ls -l /dev/serial/by-id/` shows your adapter, and you have written the path down

Repeat for the second gateway if you are building both roles. Then continue with
[chapter 1 of the walkthrough](walkthrough/01-prerequisites.md).
