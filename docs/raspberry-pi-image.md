# Imaging a gateway Pi

This lab **starts from a Raspberry Pi that is already booted and reachable over SSH.**
Getting to that point is standard Raspberry Pi work, it has nothing to do with FleetForge,
and it is documented here separately so the walkthrough does not have to repeat it.

Everything on this page is runnable today. It needs nothing from this repository.

## The baseline

**Raspberry Pi OS Lite, 64-bit (arm64).**

- **Lite**, because a gateway has no display. A desktop image adds attack surface and
  disk usage for nothing.
- **64-bit**, because the container images this lab runs are pulled for `arm64`.

The exact OS release this lab is qualified against is recorded in
[Hardware and versions](hardware-and-versions.md) — currently `Unknown`, and it gets pinned
when WP-02 provisions a real host. Use the current stable Raspberry Pi OS release and
record what you used.

## Write the image

Use Raspberry Pi Imager. Choose *Raspberry Pi OS (other)* → *Raspberry Pi OS Lite (64-bit)*.

Before writing, open the **OS customisation** settings and set:

| Setting | Why |
|---|---|
| Hostname | A distinct name per gateway. The lab addresses hosts by inventory alias, so pick something you will recognise |
| Username and password | Avoid the historical default username; this account will hold sudo |
| **Enable SSH → public-key only** | Password SSH on a device that runs your radio network is not worth the convenience |
| Wi-Fi (if not using Ethernet) | Ethernet is steadier, but either works. This lab makes no network demands |
| Locale and timezone | The timezone matters: your logs and your lamp observations need to agree |

Write the card, put it in the Pi, and power it on.

## Confirm you can reach it

```sh
ssh <user>@<your-pi-hostname>
```

From the Pi, confirm the two facts the lab depends on:

```sh
uname -m          # expect: aarch64
sudo -n true && echo "sudo ok"
```

If `uname -m` does not say `aarch64`, a 32-bit image was written and the container images
will not run. Re-image before going further.

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

## A note on USB serial adapters

Some Linux systems run a modem-management service that opens USB serial devices it finds,
looking for a modem. When it grabs a radio adapter, the adapter looks dead to the protocol
service — a failure that reads as broken hardware.

Handling that is part of host provisioning (WP-02), not part of imaging. It is mentioned
here so that a dead-looking adapter on a fresh host is not mistaken for a hardware fault.

## You are ready when

- The Pi boots and you can SSH in with a key
- `uname -m` reports `aarch64`
- `sudo` works without an interactive password prompt
- `ls -l /dev/serial/by-id/` shows your adapter, and you have written the path down

Repeat for the second gateway if you are building both roles. Then continue with
[chapter 1 of the walkthrough](walkthrough/01-prerequisites.md).
