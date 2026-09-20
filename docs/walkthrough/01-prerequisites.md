# 1. Prerequisites and hardware

**Status: usable now.** Nothing on this page needs code from this repository.

## What you are building

One or two Raspberry Pi gateways. Each is one Pi, one USB radio, one smart wallplug and
one lamp:

```text
lamp ── wallplug ──radio──▶ USB adapter ──▶ Raspberry Pi ──network──▶ your workstation
```

The lamp is the point. It is the only part of this lab that tells you the truth without
being asked.

## Hardware

| Item | Per gateway | Notes |
|---|---|---|
| Raspberry Pi | 1 | Raspberry Pi 4 Model B, with a power supply and SD card |
| Network | 1 | Ethernet or Wi-Fi. No fixed subnet, no VLAN, no router changes |
| USB radio adapter | 1 | A Zigbee **coordinator**, or a Z-Wave **controller** |
| Smart wallplug | 1 | Matching the radio protocol, with a controllable relay |
| Lamp | 1 | Anything visible from where you will be sitting |

Two cautions worth reading before you buy — a sniffer-firmware Z-Wave stick and a
mismatched Zigbee chipset both fail in ways that look like something else entirely. See
[Hardware and versions § Choosing a radio adapter](../hardware-and-versions.md#choosing-a-radio-adapter).

**Physical placement.** Keep the wallplug within comfortable radio range of its gateway for
the first pairing — a marginal link at pairing time produces intermittent behaviour later
that is hard to attribute. And if you are building both roles, put the lamps where you can
see both from one chair. You will be watching them more than you expect.

## Workstation

You drive everything from your own machine; you do not work on the Pi directly.

| Tool | Used for |
|---|---|
| `ssh` | Reaching the gateways, ideally with key authentication configured |
| `make` | The operator entry point for every lab command |
| `git` | This repository |
| Ansible | Host provisioning (from WP-02) |
| A web browser | The protocol service UIs, and later the FleetForge UI |

## The gateway hosts

Each Pi must be **booted, updated, reachable over SSH, and have its radio adapter
plugged in with the stable by-id path recorded.**

Getting there is standard Raspberry Pi work and is documented separately:
**[Imaging a gateway Pi](../gateway-os-image.md)**. Do that now if you have not already.

## Your inventory

The lab is driven from an inventory file describing your hosts — their aliases, roles,
adapter paths and service endpoints.

1. Copy [`inventory/inventory.example.yml`](../../inventory/inventory.example.yml) to a
   path **outside this repository**, or to `inventory/inventory.yml`, which git ignores.
2. Fill in your own hosts. Delete the role you are not building — either role works alone.
3. Keep secrets out of it. The inventory references **paths to files** you hold privately;
   it never contains a token, key or certificate.

Full field-by-field notes: [inventory/README.md](../../inventory/README.md).

## FleetForge access

Chapters 3 to 5 need a FleetForge control plane and the agent artifact. **Neither is
public.** Check what you have now rather than at chapter 3:
**[Software access](../software-access.md)**.

If you do not have access, chapters 1 and 2 still work end to end, and they are where the
problems this lab is about become visible.

## You are ready when

- [ ] Each Pi boots, answers SSH with a key, reports `aarch64`, has finished `cloud-init`,
      and has working passwordless `sudo`
- [ ] Each radio adapter appears under `/dev/serial/by-id/` and you have recorded the path
- [ ] Each wallplug is powered, with a lamp in it, near its gateway and visible from where
      you sit
- [ ] Your workstation has `ssh`, `make`, `git` and Ansible
- [ ] You have a private inventory file with your hosts in it
- [ ] You know whether you have FleetForge access, one way or the other

Next: [2. The standalone estate](02-standalone-estate.md).
