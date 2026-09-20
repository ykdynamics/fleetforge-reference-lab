# Hardware and versions

## How this lab selects hardware and versions

Two rules, and they are the reason this page is mostly empty:

1. **A version is pinned when a procedure in this repository has been run against it** on
   real hardware, and the result recorded. Not when it seemed to work once, and not
   because it is the current release.
2. **A compatibility claim requires evidence.** Until then the entry is `UNKNOWN`. An
   `UNKNOWN` here is not a warning that something is broken — it means nobody has run the
   documented procedure against it yet.

Where a pin exists, it is applied in the actual configuration — the Compose image tags,
the Ansible package versions — and not only described here. Floating tags such as
`latest` make a lab that worked yesterday fail today for reasons that have nothing to do
with what you changed.

## Support matrix

Status values: **Qualified** (this repository's procedure was run against it and recorded)
· **In use** (the author's bench runs it; not qualified by this repository's procedure)
· **Unknown** (untested here).

| Component | Version | Status | Evidence |
|---|---|---|---|
| Raspberry Pi model | 4 Model B | In use | The lab baseline. Other models are untested here |
| Ubuntu Server LTS (arm64) | 24.04 | In use | The supported baseline. `make preflight` warns on anything else |
| Docker Engine | 29.8.1 | Qualified (provisioning) | Installed by `make provision` on both hosts |
| Docker Compose plugin | 5.5.1 | Qualified (provisioning) | Installed by `make provision` on both hosts |
| Mosquitto | 2.1.2-alpine | Qualified (service start) | Started and answered a local subscribe on both hosts |
| Zigbee2MQTT | 2.14.1 | Qualified (coordinator start) | Started; coordinator answered |
| Z-Wave JS UI | 11.24.1 | Qualified (controller start) | Started; driver ready, controller identified |
| zwave-js (driver) | 15.29.0 | Qualified (controller start) | Bundled with Z-Wave JS UI 11.24.1 |
| Zigbee coordinator adapter | Sonoff ZBDongle-P (CC2652P, CP210x bridge) | Qualified (coordinator start) | Driver `zstack`; reports `ZStack3x0`, firmware revision 20210708 |
| Z-Wave controller adapter | Zooz ZST39 LR (800 Series Long Range) | Qualified (controller start) | Identified by zwave-js as node type **Controller** |
| Zigbee wallplug | Sonoff S60ZBTPF | Qualified (paired, metering observed) | Reports live `power`/`current`; `voltage` refreshes only on explicit read |
| Z-Wave wallplug | Fibaro FGWP-102 | Qualified (included, switched, metering observed) | Binary Switch CC 37 for control, Meter CC 49 for power |
| FleetForge control plane | local development deployment | In use | Plain HTTP on the workstation; a TLS deployment is the next step |
| FleetForge agent | 0.1.1-lab (arm64 .deb) | Qualified (enrolled, observing, operating both protocols) | Built from the product repository; not publicly downloadable |
| Ansible (workstation) | — | Unknown | To be pinned in WP-02 |

The OS baseline moved from Raspberry Pi OS Lite to Ubuntu Server 24.04 LTS when the
lab hardware was prepared. One baseline is supported, not both: the two differ in
first-boot handling (`cloud-init`), networking (`netplan`) and which services claim USB
serial adapters, and carrying both would double the provisioning surface for no gain.

A separate matrix records **what has been demonstrated**, which is a different question
from what version is installed:

| Exercise | Zigbee role | Z-Wave role |
|---|---|---|
| Standalone lamp OFF/ON via the protocol UI | **PASS** — OFF and ON, human-observed, lamp restored | **PASS** — OFF and ON, human-observed, lamp restored |
| Agent enrolled and heartbeating | **PASS** — online, agent 0.1.0-lab | **PASS** — online, agent 0.1.0-lab |
| Devices visible in FleetForge with observation timestamps | **PASS** — plug visible, attributed to its gateway | **PASS** — node visible, attributed to its gateway |
| Lamp OFF/ON **through FleetForge** | **PASS** — OFF and ON, human-observed | **PASS** — OFF and ON, human-observed, after [fleetforge#415](https://github.com/ykdynamics/fleetforge/issues/415) |
| Re-run integration preserving gateway identity | **PASS** — no new record created | **PASS** — upgraded in place, identity kept |
| Reset and rebuild from published instructions alone | Unknown | Unknown |

Both columns are filled in independently. See
[Evidence conventions § Z-Wave support is established, never inherited](evidence-conventions.md#z-wave-support-is-established-never-inherited).

> **On prior results.** A Zigbee lamp had previously been switched through FleetForge on
> the author's bench and confirmed visually, before this repository existed. Every row
> above was re-established by this repository's own procedure rather than inherited.
>
> Keeping the two protocols separate paid for itself: Z-Wave control turned out to be
> impossible on the then-current product build, for a reason no automated signal reported.
> Had the Zigbee result been read as evidence for both,
> [fleetforge#415](https://github.com/ykdynamics/fleetforge/issues/415) would have shipped
> as a working feature.

## Choosing a radio adapter

The lab does not require specific models, but two things matter more than the brand:

**Confirm the stick is a controller.** Some Z-Wave USB sticks ship with packet-sniffer
firmware. They present the same USB identity and the same device node as a controller, the
service starts normally, and then nothing ever pairs — which reads as a pairing problem
and is not one. Verify the firmware role before concluding anything about your mesh.

**Know which Zigbee chipset you have.** Zigbee2MQTT needs to be told which adapter driver
to use, and visually similar dongles from the same vendor can use different chipsets that
enumerate identically over USB. Getting it wrong produces a service that starts and then
fails in a confusing way. Record the chipset in your inventory alongside the adapter path.

## Always use a stable adapter path

`/dev/ttyUSB0` and `/dev/ttyACM0` are assigned in enumeration order and can change across
a reboot or a replug. With two gateways and two radios, a service pointed at the wrong
stick fails in ways that look like a broken mesh.

Use the by-id path instead:

```sh
ls -l /dev/serial/by-id/
```

That path is derived from the adapter's own identity and survives reboots. The inventory
takes a by-id path; see [inventory/inventory.example.yml](../inventory/inventory.example.yml).
