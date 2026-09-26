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
| **Radio adapter reset** | The network held in the **adapter itself**, plus the service's copy | The host, Docker, the agent and its identity | `CONFIRM=HOST` |
| **Full host reset** | The lab's data, services, agent and identity on that host | The OS, your SSH access, host provisioning (Docker, masked services) **and the adapter's own radio network** | You are rebuilding that gateway from scratch |

They are deliberately **four targets**, not one target with a flag. A single `reset` with
options is how somebody destroys a radio network while meaning to restart an agent.

## Rules that apply to all of them

**One named host at a time.** No target takes a list, and none has an "all" mode. There is
no path to an implicit estate-wide wipe.

**Destructive targets require a matching confirmation.** `CONFIRM=` must equal `HOST=`. A
mismatch fails before anything happens — including the mismatch that matters most, naming
a *different real host* in the confirmation:

```text
$ CONFIRM=lab-gw-b make agent-remove HOST=lab-gw-a
REFUSED this destroys the above on lab-gw-a.
Re-run with CONFIRM=lab-gw-a to proceed. Nothing has been changed.
```

The confirmation has to name the host, so "wrong window, right command" stops being one
keystroke away from a wiped mesh.

**Effects are printed before the destructive step**, naming what will be lost — especially
pairings and identity — and the step is refused if the confirmation does not match.

**The control plane is never reset from here.** If a reset leaves a stale gateway record
behind, retire it through FleetForge's own interface, deliberately.

## 5.1 Scenario restoration — available now

```sh
make scenario-restore HOST=<alias> ROLE=<role> DEVICE=<alias>
```

Returns the lamp to its documented baseline state. Destroys nothing, needs no confirmation,
and is the right thing to run after a half-finished exercise. This is what you want the
overwhelming majority of the time.

## 5.2 Agent removal — available now

```sh
make agent-remove HOST=<alias> CONFIRM=<alias>
```

Removes the FleetForge agent and its configuration. The radio stack, the pairings and the
protocol data are untouched — you get the chapter-2 estate back, still working.

**The enrolment identity file is kept by default.** Removing an agent in order to reinstall
it should not cost the gateway its identity, its history or its device attribution.
Discarding identity is opt-in (`PURGE_IDENTITY=1`), and it means the host will enrol as a
**new** gateway next time, leaving the old record behind for you to retire.

> You do **not** need this to see the "before" state. The standalone estate is still there
> underneath a working agent — that is the point of chapter 3. Remove the agent because you
> want it gone, not to illustrate something.

## 5.3 Protocol-data reset — available now

```sh
make protocol-data-reset HOST=<alias> ROLE=<role> BACKUP_DIR=<path> CONFIRM=<alias>
```

**This destroys the radio network and every pairing on that gateway.** Every device must be
physically re-paired afterwards, which means handling each one.

Take a backup first — this one is available now:

```sh
make radio-backup HOST=<alias> ROLE=<role> BACKUP_DIR=<private-path> DRY_RUN=1
make radio-backup HOST=<alias> ROLE=<role> BACKUP_DIR=<private-path> STOP_SERVICES=1
```

`BACKUP_DIR` must be an absolute path outside this repository; a relative one is refused.
The dry run reports the size and file count and touches nothing else — it never prints the
directory's contents, because that is where the network key lives.

`STOP_SERVICES=1` stops the radio service for the archive and starts it again afterwards.
Worth using: a running service can be mid-write, and an archive taken underneath it may
restore to a state the service never actually had.

The archive is streamed over SSH and written on your machine, never staged on the gateway
— a later disk-space problem on that host is exactly when you would want the backup
somewhere else. It lands mode `0600` in a `0700` directory, with a SHA-256 manifest that
is **verified after writing**, because a checksum nobody checks is decoration.

What a run looks like:

```text
-- verifying --
PASS archive is readable (16 entries)
PASS checksum verified after writing
```

**The agent's enrolment identity is deliberately not in the archive.** It has a different
lifecycle and a different owner, and sweeping it into a radio backup invites restoring a
gateway's identity from a stale copy and minting a confusing duplicate. Both roles were
checked for this on the bench: neither archive contains the enrolment file.

What each role's archive actually holds, confirmed by listing the entries:

| | Contents that matter |
|---|---|
| Zigbee | `coordinator_backup.json`, `database.db`, `configuration.yaml` (which carries the network key) |
| Z-Wave | `nodes.json`, the controller's node database keyed by home id, `settings.json` |

**On what a backup can actually restore.** It restores the protocol service's *stored
state*. It is not a universal promise of radio-network restoration: some adapters hold
network identity in the adapter itself, and restoration behaviour is adapter-specific. The
procedure reports the limit that applies to your adapter instead of implying the pairings
will simply come back. Plan to re-pair.

## 5.3b Radio adapter reset — available, not yet run on hardware

> **Verified on both roles.** Zigbee: the coordinator formed a network with a new
> `ext_pan_id` and started cleanly with no panId collision. Z-Wave: the controller took a
> new home id and came back with only itself on the network. In both cases the device was
> re-paired by hand and returned through the agent into FleetForge **without re-enrolling
> the gateway**, and the lamp was switched through FleetForge afterwards.

```sh
make radio-adapter-reset HOST=<alias> ROLE=<role> CONFIRM=<alias>
```

This is the reset the other three cannot do. They clear what the protocol *service* stores;
they cannot clear what the **adapter** stores, and a Zigbee coordinator keeps its network in
its own NVRAM. Wipe one side and not the other and the gateway does not start at all:

```text
error: network commissioning timed out — most likely network with the same panId
       or extendedPanId already exists nearby
```

The service is trying to form a new network while the stick still holds the old one.

**This is the one reset a backup cannot undo.** Restoring an archive re-creates the
service's files; it cannot put an old network back into a stick that has been told to
forget it. Reach for this when the two sides have diverged and the service will not start,
or when you deliberately want a new network.

The two roles reconcile differently, because the services expose different things:

| | How |
|---|---|
| Zigbee | No bridge request clears the coordinator's NVRAM, so it goes the other way: the stored network is cleared and a configuration seeded with `network_key`, `pan_id` and `ext_pan_id` all set to `GENERATE`. The service forms a genuinely new network, and new identifiers mean no collision with whatever the stick still holds |
| Z-Wave | Z-Wave JS UI exposes the controller's own factory reset. That is a true adapter-side reset — the controller forgets its home id and every node — and the target waits for the controller to confirm rather than assuming the request landed |

### Four things the Z-Wave run taught that the Zigbee one did not

**1. Your devices do not know the controller was reset.** A controller factory reset leaves
every device still believing it is included, and the controller can no longer exclude them
because it has forgotten they exist. Each device must be **factory reset from its own
side** before it will join anything. For the plug used here that is: hold the button until
the LED ring glows yellow, release, then single-click to confirm — and only then the
inclusion press. Two failed attempts on the bench were nothing but this missing step.

**2. The inclusion window is not as long as you asked for.** Z-Wave JS UI times inclusion
out after `commandsTimeout` seconds and falls back to **30** when that is unset. A target
announcing four minutes while the controller allowed thirty seconds is worse than useless:
it sends someone to stand at a plug pressing a button into a window that closed while they
were reading the instructions. `radio-join-open` now sets that timeout from `MINUTES` so
the number it prints is the number you get.

**3. `success` is not `result`.** `startInclusion` answers `success: true` for a call it
accepted and `result: false` when inclusion did not actually start — which is what happens
if a window is already open. Checking only `success` reports an open window that is not
there.

**4. The broker keeps the dead network alive.** Retained MQTT state survives the reset, so
every node of a network that no longer exists still answers a subscribe. On the bench a
node showed as present with a `lastActive` **ten hours old**, listed beside the real one.
The reset now clears those topics — 48 of them, in that run. Without it the device
inventory confidently describes hardware the controller has forgotten.

Afterwards the adapter and the service agree on an empty network, and every device must be
re-paired. On the bench the service reported `Currently 0 devices are joined` and the
device registry agreed — worth checking both, because `coordinator_backup.json` still
listed a stale device count that the live registry did not.

Three things to expect after re-pairing: the plug returns in whatever state its
`power_on_behavior` dictates (ours came back **off**), its accumulated `energy` resets, and
on Z-Wave **the node id changes** — ours came back as node 2 where it had been node 9, with
no location segment in its topic. Update `protocol_ref` in your inventory or every device
target will address something that no longer exists. **Your inventory still names the old device**, so update `protocol_ref` after
re-pairing or the lamp targets will address something that no longer exists.

## 5.4 Full host reset — available now

```sh
make host-reset HOST=<alias> CONFIRM=<alias>
```

Removes everything this lab installed on the **named** host: the agent and its identity,
the stacks, the volumes and the lab directories. The OS and your SSH access remain, so the
host is ready to be provisioned again from [chapter 2](02-standalone-estate.md).

Use this on hardware you are willing to rebuild. It is the right tool for qualifying the
walkthrough from a clean start, and the wrong tool for almost anything else.

## The same reset does very different things per protocol

Both roles have now been rebuilt from `host-reset` through to operating the lamp. The
sequence is identical; the outcome is not, and the difference is the single most useful
thing in this chapter.

| | Zigbee | Z-Wave |
|---|---|---|
| After `host-reset` | the service **will not start** | starts normally |
| Why | the coordinator keeps the network in its own NVRAM, so the service forms a *new* one alongside the old and they collide on panId | the controller keeps the network **and the node list**, so the service reads both back |
| Devices | must be **re-paired by hand** | **rediscovered automatically** — `[Node 002] Ready … Interview COMPLETED`, no re-inclusion |
| Recovery needed | restore a backup, or `radio-adapter-reset` | none |

On the bench the Z-Wave gateway came back on the **same home id** it had before the wipe,
found its plug unassisted, and was switched through FleetForge minutes later. The Zigbee
gateway, given the same command, was dead until a backup was restored.

So "I reset the gateway" is not one fact. On Z-Wave it is nearly free; on Zigbee it costs
you the mesh unless you have a backup or reset the adapter too. Anyone reasoning about one
protocol from experience with the other will be wrong, and wrong in the expensive direction.

**What `host-reset` costs on both:** the agent's enrolment identity, so the gateway enrols
afresh and the old record is stranded. Retiring it now works — archive then delete — which
it did not before [fleetforge#418](https://github.com/ykdynamics/fleetforge/issues/418).

## What a clean start actually found

The rebuild was run on the Zigbee gateway: `host-reset`, then the published instructions
from provisioning through to operating the lamp. Four things came out of it, and none of
them was visible before somebody did it.

### 1. `host-reset` leaves a Zigbee gateway unable to start

This is the important one. The reset wipes the protocol service's data — including the
network key and the coordinator backup — so Zigbee2MQTT starts fresh and tries to form a
**new** network. But the coordinator stick still holds the **old** network in its own
NVRAM. The two collide:

```text
error: network commissioning timed out - most likely network with the same panId
       or extendedPanId already exists nearby
```

The stack does not start at all. Not degraded — down.

This is the "some adapters hold network identity in the adapter itself" caveat from the
backup section, arriving from the other direction: it is not only that a restore may fail
to reconstitute a mesh, it is that **deleting the service's data while the adapter keeps
its network leaves the gateway broken** until one side or the other is reconciled.

So a Zigbee `host-reset` or `protocol-data-reset` is not complete on its own. Either
restore a backup, or reset the adapter itself.

### 2. The backup restored everything, including the pairing

Recovery was the backup, and it worked:

```text
checksum          verified before the archive was trusted
Coordinator firmware version: ZStack3x0
Currently 1 devices are joined.
Zigbee2MQTT started!
```

**No device had to be re-paired.** The adapter had kept the network, the archive supplied
the matching key and device database, and the two agreed again. That is a stronger result
than the backup section promised — and the promise stays deliberately weaker, because it
held here only because the same physical adapter was still in place.

### 3. `host-reset` keeps more than the documentation said

The first preflight after the reset reported **zero warnings** on a supposedly fresh host:
Docker still installed, ModemManager still masked. `host-reset` removes the lab's data,
services and agent — it does not undo host provisioning.

That is defensible behaviour: removing Docker would be heavy-handed, and re-provisioning
is idempotent anyway. But "everything the lab installed" overstated it. What it really
gives you is a **lab-clean host, not a day-zero one**, and the table above now says so.

A genuinely day-zero qualification starts from a freshly imaged card.

### 4. A fresh enrolment duplicates records, and the stale one cannot be deleted

Expected: the rebuilt gateway enrolled as a new record and the old one was left behind.
The documentation said it would be.

Not expected: **the same physical device now appears twice** — once online under the new
gateway, once offline under the old one — and the documented retirement path does not
complete. Archiving works; deleting fails, because the old gateway has command history and
a foreign key holds it in place. Worse, the failure is reported as a **retryable** error
for a condition that will never clear.

Tracked as [fleetforge#418](https://github.com/ykdynamics/fleetforge/issues/418). Until it
is fixed, expect a rebuilt gateway to leave a permanent archived record and a duplicate
device behind.

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
