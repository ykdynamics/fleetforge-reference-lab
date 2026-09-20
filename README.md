# FleetForge Reference Lab

A small, reproducible IoT lab you can build on your own desk: two Raspberry Pi gateways,
two radio protocols, two lamps — operated first **without** FleetForge, then **with** it,
so the difference is something you observe rather than something you are told.

> **Status: early.** This repository currently contains the lab contract — the guide
> structure, the architecture and scope, the example inventory, the operator command
> contract and the evidence rules. **The automation is not written yet.** Nothing here
> provisions a host or switches a lamp today. See
> [What exists today](#what-exists-today) before planning an evening around it.

---

## What this lab teaches

Most IoT demonstrations show you a finished dashboard. This one makes you build the
un-finished thing first, because the problems FleetForge addresses are only obvious once
you have felt them:

1. **A working estate is not a managed estate.** Two gateways, each with its own web UI,
   its own broker, its own idea of what is paired. Nothing tells you which one is stale.
2. **Different protocols are genuinely different.** A Zigbee lamp and a Z-Wave lamp are
   not interchangeable, and a control path proven on one is not proof for the other.
3. **"The command succeeded" is three different claims.** Queued, acknowledged, and
   physically happened are separate facts. This lab keeps them separate on purpose — see
   [Evidence conventions](docs/evidence-conventions.md).
4. **Adding a control plane should not cost you your estate.** FleetForge is added
   alongside the protocol services you already have. You do not re-pair devices, and you
   do not tear down what works in order to demonstrate the "before" state.

What you end up with is a lab you can rebuild from these instructions alone — not from
somebody's chat history.

## What you need

| | |
|---|---|
| **Gateways** | 1–2 Raspberry Pi (64-bit capable), each with a power supply, SD card and network |
| **Radios** | A Zigbee coordinator USB stick, and/or a Z-Wave controller USB stick |
| **Devices** | One smart wallplug per role, and a lamp to plug into it |
| **OS** | Raspberry Pi OS Lite, 64-bit, already imaged and reachable over SSH |
| **Workstation** | Linux or macOS with `make`, `git`, `ssh` and Ansible |
| **FleetForge** | Control-plane access **and** agent artifacts — neither is public; read [Software access](docs/software-access.md) first |

Either role runs on its own. One Pi with one radio and one lamp is a complete, useful
lab; the second role exists to show that a control path proven on one protocol is not
proof for the other.

Exact hardware models and the versions this lab has actually been run against are tracked
in [Hardware and versions](docs/hardware-and-versions.md). That table is deliberately
mostly `UNKNOWN` right now — it gets filled in when a procedure is run on real hardware,
not before.

## The journey

```text
  1. Standalone            2. Integration              3. Operation
  ─────────────            ──────────────              ────────────
  Pi + radio + lamp        the same estate,            the same lamp,
  Zigbee2MQTT / Z-Wave JS  plus a FleetForge agent     switched through FleetForge
  a local broker           enrolled alongside it       with run and command receipts
  a protocol web UI
                                                       4. Reset / repeat
  You switch the lamp      Nothing is re-paired.       ────────────────
  from the protocol UI.    Nothing is uninstalled.     Restore the scenario, or
  It works. It is also     The "before" estate is      remove the agent, or wipe
  entirely local and       still there underneath.     the radio data — each is a
  entirely unmanaged.                                  separate, explicit action.
```

Read it in order: [the walkthrough](docs/walkthrough/README.md).

## What exists today

| Deliverable | Status |
|---|---|
| Lab contract, architecture and scope | **Available** — [architecture-and-scope.md](docs/architecture-and-scope.md) |
| Ordered walkthrough (5 chapters) | **Available as structure**; standalone and FleetForge steps are marked planned |
| Prerequisites and Pi imaging | **Available and runnable** — standard OS steps, no repo code needed |
| Example inventory | **Available** — [inventory/](inventory/) |
| Operator command contract | **Available as a contract** — [command-contract.md](docs/command-contract.md); no target is implemented |
| Evidence conventions | **Available** — [evidence-conventions.md](docs/evidence-conventions.md) |
| Software-access requirements | **Available** — [software-access.md](docs/software-access.md) |
| Host provisioning (Make + Ansible) | **Planned** — WP-02 |
| Standalone Zigbee / Z-Wave stacks | **Planned** — WP-03 |
| FleetForge agent integration | **Planned** — WP-04 |
| Guided lamp exercise and evidence | **Planned** — WP-05 |
| Reset, rebuild and first-use qualification | **Planned** — WP-06 |

The only commands this repository implements today are its own documentation checks:

```sh
make help     # what is actually implemented here
make check    # validate relative links and example-file syntax
```

Every operator command named in the [command contract](docs/command-contract.md) is a
**proposal**, not an implementation. This repository does not ship targets that exit `0`
while doing nothing.

## Next steps

1. Read [Software access](docs/software-access.md) — the FleetForge parts of this lab need
   access you may not have, and it is better to find that out now than at chapter 3.
2. Read [Architecture and scope](docs/architecture-and-scope.md) — what the two gateway
   roles do, what FleetForge adds, and what this lab deliberately excludes.
3. Work through [the walkthrough](docs/walkthrough/README.md) as far as the current status
   allows: chapters 1 and the imaging notes are usable today.
4. Copy [`inventory/inventory.example.yml`](inventory/inventory.example.yml) to a private
   location and fill in your own hosts. Your real inventory is ignored by git on purpose.

## How this repository relates to the others

| Repository | Owns |
|---|---|
| **fleetforge-reference-lab** (this one, public) | The standalone estate, provisioning, the integration guide and the repeatable exercises |
| **fleetforge** (private) | The product: control plane, agent behaviour, supported APIs, and product defects |
| **fleetforge-showcase** (private) | Presentation and narrative; it links to this lab once the lab is runnable |
| Your private operator configuration | Real inventory, credentials, certificates, radio network keys and raw evidence |

A bug in FleetForge belongs in `fleetforge`. A gap in how to set the lab up belongs here.
See [Architecture and scope § Public and private boundaries](docs/architecture-and-scope.md#public-and-private-boundaries).

## Licensing

**This repository has no license file yet**, which means default copyright applies and no
reuse rights are granted. Choosing one is a deliberate decision for the repository owner,
and it also gates how much existing automation can be brought in — see
[Reuse audit](docs/reuse-audit.md).
