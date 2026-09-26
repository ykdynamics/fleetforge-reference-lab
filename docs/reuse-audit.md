# Reuse audit

Substantial gateway automation already exists in the private `fleetforge` repository,
under the reproducibility issue
[fleetforge#389](https://github.com/ykdynamics/fleetforge/issues/389). WP-01 audited it
before designing anything, so that later work packages **reconcile with it rather than
grow a competing copy**.

This page records what was found, what should be reused, and what has to be decided before
any of it can move.

## Nothing has been copied

No file, script or configuration from the private repository has been brought into this
public repository, and none will be until the questions at the bottom of this page are
answered. The audit is a reading exercise; the outcome is this list.

## What already exists

Found in `fleetforge/lab/` — a Make-driven operator surface over shell helpers, Compose
service definitions and per-role agent installation. In fleet-automation terms it is
mature: it already follows most of the conventions this lab wants.

| Area | What exists there | Value to this lab |
|---|---|---|
| Operator surface | A Make interface over small shell helpers, with explicit `HOST=` / `ROLE=` selection | **High** — this lab's [command contract](command-contract.md) is deliberately shaped to match it |
| Read-only preflight and health | Host, adapter, container, listener and agent checks that already emit PASS/WARN/UNKNOWN and refuse to print secrets | **High** — the closest thing to a direct port |
| Protocol service definitions | A single Compose file serving both roles via profiles, with persistent volumes and bounded logging | **High** — would save WP-03 significant rediscovery |
| Agent installation | Per-role collector configuration, enrollment identity preserved across upgrades, CA material handled as a file | **High** — WP-04 should reuse this shape rather than re-derive it |
| Radio-state backup | Volume archiving with a checksum manifest, a dry-run mode, and secrets excluded | **High** — WP-03/WP-06 |
| Evidence vocabulary | PASS / WARN / FAIL / UNKNOWN with meanings, and the "heartbeat is not device freshness" rule | **Adopted already** — reproduced as [Evidence conventions](evidence-conventions.md), written independently rather than copied |
| Hard-won operational lessons | Sniffer-vs-controller firmware, Zigbee chipset/driver mismatch, unstable `/dev/tty*` numbering, several coordinators competing for a joining device, unbounded container logs filling a disk while heartbeats stayed green | **High, and already used** — these are described in this repository in our own words, with no configuration or identifiers carried over |
| Developer-only tooling | Sketch flashing, simulators, load generation, other board families, bench evidence collection | **Out of scope** — belongs to product development, not to this lab |

Also reviewed: the private showcase repository, which holds the estate narrative and
presentation. That stays where it is. This lab is the runnable path the showcase links to;
duplicating its narrative here would create a second thing to keep true.

## What cannot be carried over as-is

Even with permission, some of it needs rework before it can be public:

- **Bench-specific defaults.** Host aliases, a three-Pi topology, a hardcoded SSH user, a
  laptop control plane and LAN address detection. This lab has no default host and no
  assumed network.
- **A three-gateway estate.** This lab's contract is two roles, each independently
  runnable.
- **Development paths.** Building the agent from source, local package building and
  developer smoke tests assume a product working copy that a lab user does not have.
- **Ansible coverage.** The existing automation is Make-and-shell heavy; host provisioning
  here is Ansible's job, per the architecture. Some shell would become tasks rather than
  being copied.
- **Operational evidence.** Real gateway identifiers, device addresses and timings stay
  private. Only sanitised shapes are publishable.

## Recommendation

Reuse the **shape** in all cases, and the **text** only where the licensing question below
is answered affirmatively:

1. **Adopt the operator conventions now.** Explicit `HOST=`/`ROLE=` selection, read-only
   before mutating, fail-closed on missing arguments, PASS/WARN/FAIL/UNKNOWN. This costs
   nothing and is already reflected in the command contract.
2. **Port the read-only checks first** — the least risky code to move, and the most useful
   early.
3. **Keep one source of truth per procedure.** Where a procedure moves here, the private
   copy should point at this repository rather than diverge. `fleetforge#389` stays open
   for what remains product-side; it is not closed just because this lab exists.
4. **Do not port developer tooling.** It belongs with the product.

## Open questions for the repository owner

These are material and block WP-02 onward. None can be resolved from repository evidence.

### 1. This repository's licence — settled

**Apache License 2.0.** Chosen for the patent grant and the `NOTICE` mechanism, which
matter more than usual here: the lab sits next to a product that may be licensed
commercially, and an explicit patent grant protects both sides of that boundary.

Readers now have clear rights to the lab's automation, configuration and documentation.
That does not extend to FleetForge or to the third-party services the lab runs, and
[NOTICE](../NOTICE) says so.

### 2. The source material is still unlicensed

`fleetforge` is private and carries no licence file, so moving code out of it remains a
publication decision for the owner. The outbound direction is now settled — anything that
lands here is Apache-2.0 — but the owner still has to decide that a given file may leave
the private repository at all.

**In practice this has largely stopped mattering.** WP-02 and WP-03 wrote their automation
fresh: preflight, provisioning, the protocol stacks, device inspection and the lamp
exercise are all original work here, and several of them ended up better for it — the
adapter-level ModemManager check and the payload-age freshness reporting came from
measuring this hardware rather than from inherited code.

The one remaining candidate is the radio-state backup with its checksum manifest, which
WP-06 needs. Everything else can stay where it is.

### 3. FleetForge artifacts stay gated — settled, and revisitable

The control-plane and agent images are private; an unauthenticated pull is rejected
(`403`). They stay that way for now, and the reasoning is recorded here so the decision can
be revisited on evidence rather than re-argued from scratch.

**It is a one-way door.** Publishing a package later is a click. Un-publishing one that
people have pulled and built against is not, and it would land at the worst moment —
when somebody's lab breaks. With reversal costs that asymmetric, the reversible side wins
until there is a reason to move.

**Public artifacts optimise for the wrong thing right now.** They serve volume of
unattended trials. What the product needs is a small number of deep engagements, and in
those access is provisioned as part of the engagement anyway — so gating costs nothing
there.

**The lab does not depend on it.** Chapters 1 and 2 need nothing private and are the half
that makes the case at all: a reader who builds them has *felt* the problem rather than
been shown a dashboard. That is a better place to start a conversation than an unattended
verdict.

**What would change it:** a design partner who must self-provision without the maintainers
in the loop; a decision that this lab is a marketing funnel rather than an engagement tool,
where reach matters more than control; or commercial validation landing, after which giving
away the runtime costs less.

The obligation the decision creates is answered in [Software access](software-access.md):
the gate says how to ask. A closed door is a legitimate product choice. A blank wall is
not.

### 4. Is there a control plane a lab user can point at?

The lab must not embed the author's deployment. Either a lab user deploys their own
control plane — which currently requires private repository access — or they are given
credentials for one. This bounds what "follow the guide" can mean for someone outside the
organisation.

### 5. Third-party licences — recorded

The protocol services are open source under their own licences, and this repository
configures them rather than redistributing them: the container images are pulled from
their publishers at run time. They are listed in [NOTICE](../NOTICE) so the boundary is
explicit.
