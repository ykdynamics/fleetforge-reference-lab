# 3. FleetForge integration

Add FleetForge **to the estate you just built**, without taking any of it apart.

**Assumes:** [chapter 2](02-standalone-estate.md) complete and working — services running,
device paired, lamp switchable from the protocol UI. And FleetForge access; if you have
not checked, do that now: [Software access](../software-access.md).

## The one rule of this chapter

> Nothing from chapter 2 is removed, re-paired or reconfigured.

The protocol services keep running. The broker keeps running. The wallplug stays paired to
the same coordinator with the same identity. FleetForge is **added alongside**, and reads
through what is already there.

This matters for the comparison. A "before" state you had to dismantle to demonstrate is
not a before state — it is a second setup. It also matters practically: re-pairing devices
to demonstrate a management tool would be an odd thing to ask of anyone, and would tell
you nothing about the tool.

## What gets added

```text
Raspberry Pi                          (unchanged from chapter 2)
├── Docker + Compose
├── MQTT broker
├── protocol service + its volume     same service, same pairings
└── FleetForge agent            ◀── new: a host service, not a container
        reads the local broker
        reports outbound to the control plane
        polls for commands
```

The agent is installed as a **host service**, not as another Compose service, because it
carries its own identity with a lifecycle that must survive the stack being torn down and
brought back up.

**Nothing connects inbound to the gateway.** The agent runs a cycle — collect, report,
poll, exit — and the service manager starts the next one. A gateway behind NAT works the
same as one on your desk, and no port is opened for the control plane.

## The three pieces

| Piece | Runs where | Responsible for |
|---|---|---|
| **Control plane** | Wherever you or someone else deployed it | Identity, inventory, observed state, operations and their records, the UI and API you use |
| **Agent** | On each gateway | Enrolling once, collecting from the local broker, reporting outbound, polling for and executing bounded commands |
| **Collector** | Inside the agent, per role | Speaking the protocol service's own dialect — Zigbee2MQTT topics, or Z-Wave JS topics — and mapping what it sees to devices |

The collector configuration comes from your inventory: it points at the **same** local
broker endpoint the protocol service already publishes to. That is the whole integration
seam.

## 3.1 Check your access

> **Planned (WP-04).** A single `make ff-access-check` is proposed but not implemented.
> `make agent-plan` covers most of it: it fails with an actionable message when the
> control plane or the agent artifact is missing from your inventory.

Before installing anything, confirm four separate things: the operator endpoint answers,
your credentials authenticate, the CA trust file your inventory references exists and is
readable, and the agent artifact is obtainable.

A failure here is an access problem, not a gateway problem — see
[Software access](../software-access.md).

## 3.2 Install and enrol the agent — available now

```sh
make agent-plan    HOST=<alias> ROLE=<role>     # read-only
make agent-install HOST=<alias> ROLE=<role>
```

`agent-plan` tells you what installation would change, and — importantly — **whether this
host is already enrolled**.

Enrolment works like this: an operator mints a **one-time, expiring registration token**.
The agent presents it once, and receives a durable per-gateway identity that it keeps in a
state file on the host. The token is not a long-lived credential and cannot be reused.

Two consequences shape everything about this step:

**The token is read from a file, never passed as an argument.** Command-line arguments are
visible in process listings and end up in shell history and logs. Secrets go in files with
restrictive permissions; the inventory references the path.

**Re-running integration preserves identity.** `agent-install` on an already-enrolled host
upgrades in place. The gateway keeps its identity, its history and its device attribution.
Re-running integration is a normal, safe thing to do.

If you genuinely want a *new* gateway identity, that is a different target with its own
confirmation — `agent-enroll-fresh`. It discards the existing identity and leaves the old
gateway record behind in the control plane for you to retire deliberately. Fresh
enrolment and a rerun are different operations, with different names, on purpose. See the
[command contract](../command-contract.md#planned--wp-04-fleetforge-integration).

## 3.3 Confirm the estate is visible

```sh
make agent-status HOST=<alias> ROLE=<role>      # available now, on the gateway
```

> **Planned (WP-04).** The control-plane-side views are not implemented yet; use
> FleetForge's own UI and API meanwhile.
>
> ```text
> make ff-gateway HOST=<alias>
> make ff-devices
> make ff-health  HOST=<alias> ROLE=<role>
> ```

The same checks are available in the FleetForge UI, and it is worth looking at both.

`ff-health` reports **four separate results, and never merges them**:

| | |
|---|---|
| Host and radio service | Is the stack running on the Pi? |
| Agent authentication and heartbeat | Is the agent enrolled and reporting on schedule? |
| Device observations | Are device reports actually arriving? |
| Field freshness | How old is the newest reading — and is that knowable at all? |

A gateway that heartbeats perfectly while reporting **no devices at all** is a real,
observed failure mode: the broker or radio service died and the agent kept checking in. If
these four were collapsed into one status, that estate would look green. See
[Evidence conventions](../evidence-conventions.md#1-a-gateway-heartbeat-is-not-device-freshness).

## 3.4 Do it again for the second role

Same targets, `ROLE=` changed, different collector. Enrol each gateway with its own token.

After the second role is in, the control plane shows both gateways and the devices from
**both protocols** in one inventory, each attributed to the gateway that observed it.
That is the first thing in this lab that the standalone estate could not do at all.

Run on the bench, both gateways enrolled against a local control plane:

```text
lab-gw-zigbee   online     zigbee2mqtt:<plug>   online
lab-gw-zwave    online     zwavejs:<node>       online
```

Two protocols, two gateways, one list — and each device attributed to the gateway that
observed it. Getting here required no change to either protocol service and no device was
re-paired.

**Re-running preserved identity.** A second `agent-install` reported
`ALREADY ENROLLED — the existing identity is preserved; this upgrades in place`, and the
set of gateway records was byte-identical before and after. That is the property worth
testing deliberately: an integration command that quietly minted a second record for the
same physical host would corrupt the fleet view in a way nobody notices for weeks.

## What you should not have had to do

- Re-pair or re-include any device
- Stop, reconfigure or uninstall a protocol service
- Open an inbound port, change your network, or give the gateway a fixed address
- Put a secret on a command line

If any of those became necessary, that is a defect worth reporting — in `fleetforge` if
it is product behaviour, here if it is the lab's procedure.

## What is still open at this point

You can now **see** both protocols in one place. Whether you can **operate** both from
there is a separate question, and chapter 4 answers it per role.

Specifically: Z-Wave control through FleetForge is **not** established by Zigbee control
working. Different service, different topics, different command semantics. This lab treats
it as `UNKNOWN` until demonstrated on Z-Wave, and will record it as a **blocker** with a
product issue rather than route around it if the support is not there.

Next: [4. Operation and evidence](04-operation-and-evidence.md).
