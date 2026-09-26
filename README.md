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
| **Gateways** | 1–2 Raspberry Pi 4 Model B, each with a power supply, SD card and network |
| **Radios** | A Zigbee coordinator USB stick, and/or a Z-Wave controller USB stick |
| **Devices** | One smart wallplug per role, and a lamp to plug into it |
| **OS** | Ubuntu Server 24.04 LTS (64-bit), already imaged and reachable over SSH |
| **Workstation** | Linux or macOS with `make`, `git`, `ssh` and Ansible |
| **FleetForge** | Only for chapters 3–5. Control-plane access **and** agent artifacts, neither of which is public — read [Software access](docs/software-access.md), including how to ask |

Either role runs on its own. One Pi with one radio and one lamp is a complete, useful
lab; the second role exists to show that a control path proven on one protocol is not
proof for the other.

**You do not need FleetForge to get value from this.** Chapters 1 and 2 build a working
two-protocol estate and require nothing private — and they are where the problems a control
plane solves actually become visible, rather than being described to you. Chapters 3 to 5
add FleetForge to that estate and need access you may not have; [Software access](docs/software-access.md)
says what is needed and how to ask for it.

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

Every row below has been run against real hardware — two Raspberry Pi gateways, a Zigbee
plug and a Z-Wave plug — unless it says otherwise.

| Deliverable | Status |
|---|---|
| Lab contract, architecture and scope | **Available** — [architecture-and-scope.md](docs/architecture-and-scope.md) |
| Ordered walkthrough (5 chapters) | **Runnable** — [walkthrough](docs/walkthrough/README.md) |
| Prerequisites and Pi imaging | **Runnable** — standard OS steps, no repo code needed |
| Read-only gateway preflight | **Runnable** — `make preflight` |
| Host provisioning (Make + Ansible) | **Runnable** — `make provision-plan` / `make provision` |
| Protocol stacks (broker, Zigbee2MQTT, Z-Wave JS) | **Runnable** — `make stack-up` / `stack-status` |
| Device inspection with freshness | **Runnable** — `make radio-devices` |
| Standalone lamp exercise | **Runnable** — `make lamp-off` / `lamp-on`; both roles verified, human-observed |
| FleetForge agent integration | **Runnable** — `make agent-plan` / `agent-install`; both gateways enrolled |
| Operating a lamp through FleetForge | **Verified on both protocols** — human-observed |
| Protocol-state backup with checksum | **Runnable** — `make radio-backup` |
| The four resets | **Runnable** — `make scenario-restore` / `agent-remove` / `protocol-data-reset` / `host-reset` |
| Clean-start rebuild from the docs alone | **Not yet done** — the remaining R1 gate |
| TLS control plane with a pinned CA | **Not yet done** — the lab supports it in inventory; not exercised |

The version and exercise matrices, with what each result does and does not establish, are
in [Hardware and versions](docs/hardware-and-versions.md).

## Known limitations

Worth knowing before you start, and stated here rather than discovered at chapter four:

- **FleetForge is not publicly available.** Chapters 1 and 2 need nothing private and are
  a useful lab on their own. Chapters 3 to 5 need control-plane access and agent
  artifacts. See [Software access](docs/software-access.md).
- **Pairing is manual and physical.** At two devices, automating it would cost more than
  it saves and hide what is happening.
- **A backup restores service state, not a radio network.** Some adapters hold network
  identity in the adapter, so plan to re-pair and treat a successful restore as a bonus.
- **Metering behaviour differs by device and by field.** A lit lamp can truthfully report
  zero watts, and two fields in one payload can have different ages. Chapter 2 works
  through a real example.
- **The control plane used so far is a local development deployment over plain HTTP.**
  That is not the shape a real one has.

## What the lab found

Running it produced three findings in the product, none visible from reading code or from
a green test suite — including one that made Z-Wave device operation impossible while
every automated signal reported success. See [Product findings](docs/product-findings.md).

## Next steps

1. Read [Software access](docs/software-access.md) — the FleetForge parts of this lab need
   access you may not have, and it is better to find that out now than at chapter 3.
2. Read [Architecture and scope](docs/architecture-and-scope.md) — what the two gateway
   roles do, what FleetForge adds, and what this lab deliberately excludes.
3. Work through [the walkthrough](docs/walkthrough/README.md) as far as the current status
   allows: chapters 1 and the imaging notes are usable today.
4. Copy [`inventory/inventory.example.yml`](inventory/inventory.example.yml) to a private
   location and fill in your own hosts. Your real inventory is ignored by git on purpose.
5. Run `make help` to see every implemented target, then `make preflight HOST=… ROLE=…`
   against a gateway. It is read-only and safe to run on a host you care about.

## How this repository relates to the others

| Repository | Owns |
|---|---|
| **fleetforge-reference-lab** (this one, public) | The standalone estate, provisioning, the integration guide and the repeatable exercises |
| **fleetforge** (private) | The product: control plane, agent behaviour, supported APIs, and product defects |
| **fleetforge-showcase** (private) | Presentation and narrative; it links to this lab once the lab is runnable |
| Your private operator configuration | Real inventory, credentials, certificates, radio network keys and raw evidence |

A bug in FleetForge belongs in `fleetforge`. A gap in how to set the lab up belongs here.
See [Architecture and scope § Public and private boundaries](docs/architecture-and-scope.md#public-and-private-boundaries).

## Licence

Apache License 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE). Use it, adapt it, build
on it.

Two things that licence does **not** cover:

- **FleetForge itself.** This repository is the lab, not the product. FleetForge has its
  own licensing and access terms, and a public lab source tree is not a claim that
  FleetForge is publicly available — see [Software access](docs/software-access.md).
- **The third-party software the lab runs.** Mosquitto, Zigbee2MQTT, Z-Wave JS UI, Docker
  and Ansible each keep their own licences. This repository configures and documents them;
  it does not redistribute them. They are listed in [NOTICE](NOTICE).
