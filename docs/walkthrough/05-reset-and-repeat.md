# 5. Reset and repeat

Put the lab back — to whichever point you actually mean.

"Reset" is four different operations here. They destroy different things, and the
difference between them is the difference between restarting a service and re-pairing
every device in the room.

**Assumes:** you have run some part of [chapter 4](04-operation-and-evidence.md).

## The four resets

From least to most destructive:

| Operation | Removes | Keeps | You need this when |
|---|---|---|---|
| **Scenario restoration** | Nothing | Everything | The lamp is off, or the estate is mid-exercise, and you want the documented baseline back |
| **Agent removal** | The FleetForge agent and its configuration | Radio stack, pairings, protocol data — **and the enrolment identity, by default** | You want the standalone estate back, or you are reinstalling the agent |
| **Protocol-data reset** | The protocol service's persistent data — **the radio network and every pairing on that gateway** | Host, Docker, agent and its identity | The radio state is corrupt, or you want a genuinely fresh pairing exercise |
| **Full host reset** | Everything this lab installed on that host | The OS and your SSH access | You are rebuilding that gateway from scratch |

They are deliberately **four targets**, not one target with a flag. A single `reset` with
options is how somebody destroys a radio network while meaning to restart an agent.

## Rules that apply to all of them

**One named host at a time.** No target takes a list, and none has an "all" mode. There is
no path to an implicit estate-wide wipe.

**Destructive targets require a matching confirmation.** `CONFIRM=` must equal `HOST=`. A
mismatch fails before anything happens.

**Effects are printed before the destructive step**, naming what will be lost — especially
pairings and identity — and the step is refused if the confirmation does not match.

**The control plane is never reset from here.** If a reset leaves a stale gateway record
behind, retire it through FleetForge's own interface, deliberately.

## 5.1 Scenario restoration — planned (WP-06)

> **Planned.** Proposed target, not implemented.
>
> ```text
> make scenario-restore HOST=<alias> ROLE=<role> DEVICE=<alias>
> ```

Returns the lamp to its documented baseline state. Destroys nothing, needs no confirmation,
and is the right thing to run after a half-finished exercise. This is what you want the
overwhelming majority of the time.

## 5.2 Agent removal — planned (WP-06)

> **Planned.** Proposed target, not implemented.
>
> ```text
> make agent-remove HOST=<alias> CONFIRM=<alias>
> ```

Removes the FleetForge agent and its configuration. The radio stack, the pairings and the
protocol data are untouched — you get the chapter-2 estate back, still working.

**The enrolment identity file is kept by default.** Removing an agent in order to reinstall
it should not cost the gateway its identity, its history or its device attribution.
Discarding identity is opt-in (`PURGE_IDENTITY=1`), and it means the host will enrol as a
**new** gateway next time, leaving the old record behind for you to retire.

> You do **not** need this to see the "before" state. The standalone estate is still there
> underneath a working agent — that is the point of chapter 3. Remove the agent because you
> want it gone, not to illustrate something.

## 5.3 Protocol-data reset — planned (WP-06)

> **Planned.** Proposed target, not implemented.
>
> ```text
> make protocol-data-reset HOST=<alias> ROLE=<role> CONFIRM=<alias>
> ```

**This destroys the radio network and every pairing on that gateway.** Every device must be
physically re-paired afterwards, which means handling each one.

Take a backup first:

> **Planned.** Proposed target, not implemented.
>
> ```text
> make radio-backup HOST=<alias> ROLE=<role> BACKUP_DIR=<private-path> DRY_RUN=1
> make radio-backup HOST=<alias> ROLE=<role> BACKUP_DIR=<private-path>
> ```

The backup archives the protocol service's persistent state to a private path with a
checksum manifest, excludes agent enrolment state and secrets, and never prints key
material. Run the dry run first and read what it says it will take.

**On what a backup can actually restore.** It restores the protocol service's *stored
state*. It is not a universal promise of radio-network restoration: some adapters hold
network identity in the adapter itself, and restoration behaviour is adapter-specific. The
procedure reports the limit that applies to your adapter instead of implying the pairings
will simply come back. Plan to re-pair.

## 5.4 Full host reset — planned (WP-06)

> **Planned.** Proposed target, not implemented.
>
> ```text
> make host-reset HOST=<alias> CONFIRM=<alias>
> ```

Removes everything this lab installed on the **named** host: the agent and its identity,
the stacks, the volumes and the lab directories. The OS and your SSH access remain, so the
host is ready to be provisioned again from [chapter 2](02-standalone-estate.md).

Use this on hardware you are willing to rebuild. It is the right tool for qualifying the
walkthrough from a clean start, and the wrong tool for almost anything else.

## Repeating the lab

The fresh-start exercise — standalone, integration, operation, restoration — using only the
published instructions and the documented access prerequisites is what actually qualifies
this walkthrough. Not a lint run, not a dry run, and not a green CI job.

When you run it, record what you find in
[Hardware and versions](../hardware-and-versions.md): the versions in effect, and which of
the two roles you exercised. Both roles get their own rows, and a result on one is never
published as covering the other.

Where a step failed, or needed a manual action the guide did not mention, that is the most
valuable thing you will produce. Open an issue here for a lab-procedure gap, or in
`fleetforge` for product behaviour — see
[Architecture and scope § Public and private boundaries](../architecture-and-scope.md#public-and-private-boundaries).

## Back to the start

[The walkthrough index](README.md) · [chapter 1](01-prerequisites.md)
