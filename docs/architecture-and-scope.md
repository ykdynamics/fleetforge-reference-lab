# Architecture and scope

What this lab is, what each piece is responsible for, and — just as important — what it
deliberately does not do.

## The shape

```text
workstation (yours)                 gateway host (Raspberry Pi)
───────────────────                 ──────────────────────────
make          operator entry        Docker Compose
ansible       host provisioning       ├── MQTT broker        (localhost)
ssh           transport               └── protocol service
                                          Zigbee2MQTT  (Zigbee role)
FleetForge UI / API / CLI                 or Z-Wave JS (Z-Wave role)
              fleet operations
                                    FleetForge agent (systemd, outbound only)
                                          reads the local broker,
                                          reports to the control plane,
                                          polls for commands

                                    USB radio ── wallplug ── lamp
```

Nothing connects *inbound* to a gateway from the control plane. The agent runs a cycle,
reports, polls for work and exits; the service manager starts the next cycle. A Pi behind
NAT or on a flaky link behaves the same as one on your desk.

## The two gateway roles

Each role is one Raspberry Pi, one USB radio, one wallplug and one lamp. **Either role is
a complete lab on its own.** The second role is not redundancy — it is the control.

| | **Zigbee role** | **Z-Wave role** |
|---|---|---|
| Radio | Zigbee coordinator USB stick | Z-Wave controller USB stick |
| Protocol service | Zigbee2MQTT | Z-Wave JS UI |
| Joining a device | pairing (permit-join, opened deliberately) | inclusion |
| Removing a device | unpairing / force-remove | exclusion |
| Local UI | Zigbee2MQTT frontend | Z-Wave JS UI frontend |
| Device addressing | friendly name / IEEE address | node ID |
| FleetForge observation | Zigbee2MQTT collector | Z-Wave JS collector |
| FleetForge control path | to be established in WP-04 | to be established in WP-04, **separately** |

The last row is the point of having two roles. A control path proven on Zigbee is not
evidence for Z-Wave: the topic shapes, the payloads and the service's own command
semantics all differ. This lab treats Z-Wave control through FleetForge as **unestablished
until it is demonstrated on Z-Wave**, and will record it as a blocker rather than a gap if
the product support is not there.

### Why both radios do not live on one Pi

They could, and it would be cheaper. They do not, because one host with two radios lets
you conflate "the gateway is up" with "this protocol is healthy". Two hosts make the
failure modes visible: one gateway can go silent while the other keeps reporting, which is
exactly the situation a fleet control plane exists to surface.

## Service responsibilities

| Piece | Owns | Does not own |
|---|---|---|
| **Make** | The operator entry points. One consistent way to run everything. | Any logic worth testing — it delegates |
| **Ansible** | Idempotent host configuration: packages, users, groups, directories, permissions, service units | Per-demo actions. It is not a remote-command wrapper |
| **Docker Compose** | The protocol services and their persistent data: broker, Zigbee2MQTT / Z-Wave JS, named volumes, bounded logging | Host configuration, and the FleetForge agent |
| **Protocol web UIs** | Standalone inspection, pairing/inclusion, and direct device control | Anything in the FleetForge leg of the journey |
| **FleetForge UI / API / CLI** | Fleet inspection and every operation in the FleetForge leg | The standalone baseline |
| **Shell helpers** | Small, single-purpose checks. They preserve exit status and never swallow errors | Orchestration. If it needs flow control, it belongs in Make or Ansible |

The FleetForge agent is installed by Ansible as a host service, **not** as a Compose
service, because it is a managed-host concern with its own identity and lifecycle. Its
enrollment state must survive Compose teardown — see
[Reset and repeat](walkthrough/05-reset-and-repeat.md).

## What FleetForge adds

Once the agent is enrolled, and **without touching the estate underneath it**:

- **One inventory across both protocols.** The Zigbee devices and the Z-Wave nodes appear
  as devices in one place, attributed to the gateway that observed them.
- **A distinction between gateway liveness and device freshness.** These are separate
  facts and are displayed separately. A gateway heartbeating while its observations went
  empty is a real failure mode this lab takes seriously.
- **Operations with receipts.** Switching the lamp produces a durable record — a
  capability run and a gateway command, each with an identifier and a state you can read
  back later. The standalone path produces nothing you can audit tomorrow.
- **A keyed retry contract.** A repeated request with the same idempotency key returns the
  original run instead of queueing the work twice. Details and its limits are in
  [Evidence conventions](evidence-conventions.md#retries-and-idempotency).
- **Remote reach without inbound access.** You operate a gateway you cannot SSH to.

## What FleetForge does not replace

Stated plainly, because a reader who expects otherwise will conclude the lab is broken:

- **It does not replace Zigbee2MQTT or Z-Wave JS.** They keep running, keep owning the
  radio, and keep their own UIs. FleetForge reads through them.
- **It does not re-pair, re-include or otherwise touch your radio network.** Pairing and
  inclusion stay manual and physical in this lab, by choice — at this size, the automation
  would cost more than it saves and would obscure what is actually happening.
- **It does not make command delivery certain.** An accepted operation means the request
  is durably recorded and queued for a gateway. It is not a claim about electrons.
- **It does not observe what the protocol service does not publish.** If a wallplug reports
  zero power while the lamp is visibly lit, FleetForge will faithfully show you a zero.
  That is a device or protocol-service question, not a control-plane one.

## Public and private boundaries

This repository is public. That constrains what may live here.

**Belongs here (public):**

- Provisioning and service configuration as code, with parameterised values
- The walkthrough, the command contract and the evidence rules
- Clearly fictional example inventory, and references to secret *files* by path
- Sanitised evidence: shapes, states, version numbers and relative timings

**Never here (private operator configuration):**

- Real hostnames, IP addresses, subnets, SSH configuration or user accounts
- Registration tokens, API keys, certificates and private keys
- Zigbee network keys, Z-Wave S0/S2 keys, MQTT passwords, Wi-Fi credentials
- Gateway IDs, device IEEE addresses and node identifiers from a real estate
- Raw evidence output containing any of the above

**Belongs in the product repository, not here:** FleetForge behaviour, its API contract
and its defects. If a lab procedure fails because the product is missing a capability,
the lab records a **blocker** and links to the product issue. It does not route around it
with a direct-protocol workaround dressed up as a FleetForge operation.

**Belongs in the showcase, not here:** the narrative, the screenshots and the pitch. The
showcase links to this lab once the lab is runnable.

A public lab source tree is **not** a statement that FleetForge itself is publicly
available. See [Software access](software-access.md).

## Out of scope for this release

Named explicitly so that their absence reads as a decision rather than an omission:

| Excluded | Why |
|---|---|
| **ForgeOps integration** | A separate execution-authority concern. It would double the moving parts before the basic journey works |
| **A custom management backend or dashboard** | The whole point is to use FleetForge's own UI/API/CLI. A bespoke dashboard would prove nothing about the product |
| **OTA / firmware update exercises** | Materially riskier on physical devices, and a different lesson than the one this lab teaches |
| **Kubernetes** | Compose is sufficient for a two-host estate, and it keeps the config readable |
| **New monitoring infrastructure** | Prometheus/Grafana for a two-lamp lab is infrastructure about infrastructure |
| **Network redesign** | No VLAN, no fixed subnet, no router changes and no static-IP rewrites. The lab runs on whatever network you already have |
| **Exactly-once physical execution claims** | Not offered, because it is not true. See [Evidence conventions](evidence-conventions.md) |
| **Metering as a requirement** | Consumption reporting is optional and separately unresolved. The lamp lesson does not depend on it |

## Related work packages

| | |
|---|---|
| R1 | [Reproducible two-gateway lab](https://github.com/ykdynamics/fleetforge-reference-lab/issues/7) |
| WP-01 | [Lab contract, portable inventory and newcomer guide](https://github.com/ykdynamics/fleetforge-reference-lab/issues/1) — this document |
| WP-02 | [Day-zero host provisioning and inspection](https://github.com/ykdynamics/fleetforge-reference-lab/issues/2) |
| WP-03 | [Standalone protocol stacks, pairing and lamp baselines](https://github.com/ykdynamics/fleetforge-reference-lab/issues/3) |
| WP-04 | [FleetForge integration through product interfaces](https://github.com/ykdynamics/fleetforge-reference-lab/issues/4) |
| WP-05 | [Guided FleetForge operation and outcome evidence](https://github.com/ykdynamics/fleetforge-reference-lab/issues/5) |
| WP-06 | [Rebuild/reset and complete first-use qualification](https://github.com/ykdynamics/fleetforge-reference-lab/issues/6) |
