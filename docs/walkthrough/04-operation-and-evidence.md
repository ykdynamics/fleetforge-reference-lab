# 4. Operation and evidence

Switch the same lamp — now through FleetForge — and read back what actually happened.

**Assumes:** [chapter 3](03-fleetforge-integration.md) complete: the agent enrolled, the
device visible in FleetForge, and the lamp lit.

This chapter is as much about **what you are allowed to conclude** as about the switching.

## Before you switch anything

**Prepare restoration first.** Know how you will get the lamp back on if the operation
half-succeeds, the gateway drops, or the result is ambiguous. In this lab restoration is
the protocol UI from chapter 2 — still running, still working, and untouched by anything
in chapter 3.

Agree the outcome with yourself in advance: what will count as the lamp having gone dark,
and who is going to be looking at it.

## 4.1 Switch it off

> **Planned (WP-05).** A `make ff-lamp-off` wrapper is proposed but not implemented. The
> exercise below was run through FleetForge's own API, which is what the wrapper would
> call — and using the API directly is worth doing once, because it shows you exactly
> what the product returns rather than what a wrapper chose to show you.

```text
POST /v1/capability-runs
Idempotency-Key: <your key>
{ "capability_key": "mqtt.publish",
  "input": { "gateway_id": "<gateway>", "topic": "<device set topic>", "payload": "…" } }
```

Both the target and the device are explicit. Nothing is inferred, and there is no "all
devices" form.

The operation goes through **FleetForge's own interface** — its API, with the same effect
available from its UI. There is no direct publish to the broker in this leg. Dropping down
to the protocol service here would produce a working lamp and a worthless demonstration,
since the thing under test is the control plane's path.

You get back **two identifiers**: the operation run, and the gateway command it produced.
The output says **queued**, not *switched*. That wording is deliberate and it is the whole
lesson of this chapter.

### If it times out

**Re-run the identical command with the same `KEY`.** The product deduplicates on that
key: the same key with the same input returns the original record rather than queueing a
second switch. A fresh request "just to be sure" is a second physical operation on a real
lamp.

The key is yours to choose and must be stable across retries. Details and limits:
[Evidence conventions § Retries and idempotency](../evidence-conventions.md#retries-and-idempotency).

## 4.2 Read the receipts — planned (WP-05)

> **Planned.** Proposed targets, not implemented.
>
> ```text
> make ff-run     RUN=<run-id>
> make ff-command COMMAND=<command-id>
> make ff-observe DEVICE=<alias>
> ```

These are read-only and safe to repeat. They answer three **different** questions:

| Question | Answered by | What it does not tell you |
|---|---|---|
| Was the request recorded and queued? | the run | Whether the gateway ever collected it |
| Did the agent execute its handler? | the command | Whether anything physically happened |
| What does the device say now? | the observation | Whether that report is fresh, or a retained echo |

## 4.3 Look at the lamp

Then record what you saw, as its own fact.

Human observation is **valid evidence**, and here it is usually the only trustworthy
witness of physical effect. It is recorded separately, attributed and timestamped, and it
is never merged into the automated results.

> **Planned.** Proposed target, not implemented.
>
> ```text
> make ff-exercise-record HOST=<alias> DEVICE=<alias> OUTCOME=<result> WITNESS=<witness>
> ```

The honest shapes this can take:

| What happened | Outcome | Witness |
|---|---|---|
| Command succeeded, you watched it go dark | `PASS` | `human-observed` |
| Command succeeded, nobody was looking | `UNKNOWN` | — |
| Command succeeded, device reports `OFF`, nobody was looking | `UNKNOWN` | `device-reported` |
| Command succeeded, lamp still lit | `FAIL` | `human-observed` |
| Command never left `queued` | `UNKNOWN` | — |

The second and third rows are the ones people get wrong. A successful command and a
device reporting `OFF` are **not** confirmation that the lamp went dark — the report may
be a retained echo of what was asked, and freshness is frequently unknowable. With no
independent witness, the outcome is `UNKNOWN`, and that is a correct result rather than a
failed exercise.

**If the result is inconclusive, stop and explain it.** Do not toggle again to "see if it
works this time". An extra switch is another physical operation and it destroys the
evidence you were collecting.

## 4.4 Switch it back on — planned (WP-05)

> **Planned.** Proposed target, not implemented.
>
> ```text
> make ff-lamp-on HOST=<alias> DEVICE=<alias> KEY=<a-different-key>
> ```

A new operation with its own key — it is a different request, not a retry. Record its
outcome the same way and with the same discipline.

If the ON leg does not work through FleetForge, restore the lamp from the protocol UI and
record that as what happened. A restoration performed outside FleetForge is part of the
record, not something to leave out.

## 4.5 Both roles — and a blocker on one of them

### Zigbee: works

Established on the bench. OFF and ON, both through FleetForge, both human-observed, with
run and command identifiers and a `queued: true` output that never overstated itself. The
retry contract was verified at the same time: a repeated identical request returned `200`
with the original run rather than switching the lamp twice, and the same key with a
different input was refused `409`.

### Z-Wave: blocked, then fixed, then verified

The same operation against the Z-Wave gateway **did not work**, and chasing it down is the
most useful thing in this chapter.

What was observed, in order:

```text
capability run    succeeded, attempts 1, output {"queued": true, "command_id": …}
agent log         command poll completed … commands=1
agent log         command handled … kind=mqtt_publish
broker            nothing arrived on the topic
device            unchanged — same value, same timestamp as before the request
```

**Every FleetForge-side signal said success. Nothing happened.** Queue receipt, execution
acknowledgement and physical effect are three different facts, and here the first two were
present while the third was absent. An operator reading the run status, the command status
or the agent log would have reported a working feature.

The cause was in the agent's broker allowlist. `mqtt_publish` may only publish to brokers
the agent is already configured for — a deliberate restriction, since a command free to
name any reachable address would make the agent dial it **with the gateway's broker
credentials attached**. That restriction is right and still stands.

Its membership was the defect: the allowlist was built from the Zigbee2MQTT address and
the generic MQTT address, and **the Z-Wave JS address was not in it**. On a Z-Wave-only
gateway the allowlist was therefore empty — a request naming no broker resolved to
nothing, and one naming the correct local broker was refused as a broker the agent is not
configured for.

Fixed in [fleetforge#415](https://github.com/ykdynamics/fleetforge/issues/415) by adding
that one configured address, with tests that fail without it. Then re-run here:

```text
before the fix    switch True,  power 13.3   — timestamps unchanged, nothing moved
after the fix     switch False, power 0      — both measured seconds ago
restored          switch True,  power 15.1   — both measured seconds ago
human-observed    operator reported the lamp went dark, then lit again
outcome           PASS — witness: human-observed
```

The agent was upgraded in place and kept its gateway identity, so this also demonstrates
that a product fix reaches a deployed gateway without re-enrolling it.

### What that sequence is worth

This is the whole argument for building the lab, in one episode:

- **A Zigbee lamp was already switching through FleetForge**, with receipts, human-observed
  and repeatable. Had that been taken as evidence for both protocols — which is exactly
  what a demonstration is tempted to do — this gap would have shipped as a working feature.
- **The failure was invisible to every automated signal.** Nothing short of looking at the
  device could distinguish it from success, which is precisely why this lab insists on a
  witness and treats `UNKNOWN` as a real outcome.
- **The lab refused the workarounds.** A configuration change would have made the publish
  succeed at the cost of duplicate device records, and publishing to Z-Wave JS directly
  would have lit the lamp while proving nothing about the control plane. Both were
  available, and both would have hidden a real defect.

"Z-Wave control is established, never inherited from Zigbee" reads like pedantry until it
catches something. This is what it catches.

## 4.6 Metering, if your plug has it — planned (WP-05)

Optional, and not a prerequisite for anything above.

If your wallplug reports power, current or energy, look at them with the lamp lit and
again with it dark. Record the values **with their timestamps**, and keep four states
distinct: reported zero, missing, stale, and freshness unknown.

If a plug reports zero power with a visibly lit lamp, **record the zero**. Do not
substitute a plausible number, and do not omit the reading. Whether such zeros indicate a
plug that does not meter, a mapping problem or an ingest problem is a separate
investigation — currently open as
[fleetforge#400](https://github.com/ykdynamics/fleetforge/issues/400), and not treated
here as resolved.

## What FleetForge added

Compare honestly against chapter 2 — using FleetForge's own UI, API and records, not a
dashboard built for the occasion:

| | Standalone (chapter 2) | Through FleetForge (chapter 4) |
|---|---|---|
| Inventory | Two services, two device lists | One inventory across both protocols, attributed to the observing gateway |
| Operating a device | A button in a local web UI | A recorded operation with a run and a command identifier |
| Afterwards | Nothing to inspect | Receipts and states you can read back tomorrow |
| Retrying safely | Click again and hope | A keyed contract that returns the original record |
| Gateway went quiet | You find out when you next look | Heartbeat and observation freshness reported separately |
| Reach | Only from your network | Outbound-only, from wherever the control plane is |

And what it did **not** add, stated just as plainly:

- Certainty that the lamp changed state. That still came from a person looking at it.
- Any improvement to what the plug reports. A device that reports zero power still does.
- Exactly-once physical execution. Requests are deduplicated; electrons are not.

## Publishing what you collected

Evidence published anywhere public is sanitised by hand: shapes, states, versions and
relative timings. Real gateway identifiers, device addresses, hostnames and tokens stay in
private storage. Label it `hardware` — it is not `ci` and it is not `simulated`, and those
three are never mixed.

Next: [5. Reset and repeat](05-reset-and-repeat.md).
