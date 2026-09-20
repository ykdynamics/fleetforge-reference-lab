# Evidence conventions

Every check in this lab reports one of four results, and every claim names what kind of
claim it is. This page is the contract. It applies to scripts, to the walkthrough and to
anything published as evidence.

The rules exist because the interesting failures in this estate are the ones that *look*
like success.

## The four results

| Result | Meaning | What an operator should do |
|---|---|---|
| **PASS** | The assertion was observed, now, by this check. | Nothing. |
| **WARN** | A non-blocking condition that needs a human to look at it. Includes "expected, but not confirmed". | Read it. Decide whether it matters for what you are about to do. |
| **FAIL** | An invariant is violated, or something required is unavailable. | Stop. Do not proceed to a mutating step. |
| **UNKNOWN** | Not measured, or cannot be established safely from here. | Treat as unknown. **Never** as PASS. |

`UNKNOWN` is a first-class, permanently acceptable result. A check that cannot see
something reports `UNKNOWN`; it does not guess, and it does not quietly downgrade to
`PASS` because nothing looked wrong. Most of the value in these conventions comes from
refusing to collapse `UNKNOWN` into `PASS`.

Scripts **fail closed**: a missing host, role or device argument is `FAIL`, not a default.

## Five things that are not each other

These are the specific conflations this lab refuses to make. Each has cost real time on
real hardware.

### 1. A gateway heartbeat is not device freshness

The agent can authenticate, heartbeat on schedule and look entirely healthy while
reporting **no device observations at all** — because the broker died, the radio service
crashed, or the disk filled. The fleet view stays green; the data underneath it stops
moving.

> Gateway liveness and device observation freshness are reported as separate results.
> A `PASS` on one says nothing about the other.

### 2. Queue receipt is not command completion

Submitting an operation returns a receipt meaning *the request is durably recorded and
queued for a gateway to collect*. The gateway may be asleep, offline or five minutes from
its next poll. The output says `queued` rather than `published` on purpose.

> A run identifier is proof of a request, not of a delivery.

### 3. Command completion is not physical effect

A command reaching `succeeded` means the agent ran its handler and the publish returned
without error. Between that and the lamp there is a broker, a radio, a mesh, a wallplug
and a relay — none of which reported back.

> `succeeded` is an acknowledgement. Physical effect is a separate claim requiring a
> separate witness.

### 4. Human observation is valid evidence — and is labelled as such

"The operator watched the lamp go dark" is legitimate, and in this lab it is often the
*only* trustworthy witness of physical effect. It is recorded as a human observation,
attributed and timestamped, and never merged into automated results.

> Every recorded outcome names its witness: `automated`, `device-reported` or
> `human-observed`. An outcome with no valid independent witness is `UNKNOWN`, even when
> every command succeeded.

### 5. Device-reported state is not independent confirmation

A wallplug reporting `state: ON` after you asked it to turn ON is closer to an echo than a
confirmation, especially where the protocol service retains and republishes state. It is
recorded as `device-reported` and weighted accordingly. Whether a given report is fresh or
a cached retained value is frequently `UNKNOWN`.

## Metering is optional, and zeros stay visible

The initial lamp exercise does **not** require electrical metering. Where a wallplug
reports power, current or energy, those readings are shown with their timestamps and with
four states kept distinct:

- **reported zero** — the device said zero
- **missing** — the device reports no such field
- **stale** — a value exists, but it is old
- **freshness unknown** — a value exists and nothing establishes when it was measured

A zero reading from a plug with a visibly lit lamp is **displayed as a zero**, not hidden,
smoothed or replaced with a plausible number. Whether such zeros indicate a device that
does not meter, a mapping problem or an ingest problem is investigated on its own terms
and recorded wherever it lands. Related product investigation:
[fleetforge#400](https://github.com/ykdynamics/fleetforge/issues/400) — open, and not
treated here as resolved.

## Z-Wave support is established, never inherited

A working Zigbee control path is **not** evidence for Z-Wave. Different service, different
topics, different payload semantics, different command model.

Until a Z-Wave lamp has been switched through FleetForge and the result recorded, the
Z-Wave control exercise is `UNKNOWN`. If it turns out the product lacks a needed
capability, the exercise is marked **blocked**, a product issue is filed in `fleetforge`,
and the blocker stays visible in this repository. It is never resolved by publishing to
the radio service directly and calling it a FleetForge operation.

The same applies in reverse, and to anything else: **a procedure is qualified for the
configuration it was run in, and no wider.**

## Retries and idempotency

Operations submitted through FleetForge accept a caller-supplied idempotency key. The
product's contract, which this lab uses rather than reimplements:

- A **new** key creates the operation — answered `201`.
- The **same** key with the **same** input returns the original record as it now
  stands — answered `200`. It does not queue the work a second time.
- The **same** key with **different** input is a conflict — answered `409`, and nothing is
  written.

So: on a timeout or a lost response, **resubmit the identical request with the same key**.
Never submit a fresh request "just to be sure" — that is a second physical switch of a
real lamp.

This is deduplication of *requests*. It is explicitly **not** exactly-once physical
execution, and this lab makes no such claim.

## Recording an outcome

Every exercise result records, at minimum:

```text
what was asked      the operation, its explicit target, and the key used
receipts            the run and command identifiers, with their final states
device-reported     what the device said afterwards, with a timestamp and freshness
human-observed      what a person saw, attributed and timestamped, or "not observed"
outcome             PASS | WARN | FAIL | UNKNOWN, with the witness that justifies it
versions            service, agent and adapter versions in effect
```

An exercise where every command succeeded and nobody looked at the lamp is a successful
*request* and an `UNKNOWN` *outcome*. That is the correct and expected result, not a
defect in the exercise.

## Publishing evidence

Evidence published in this public repository is sanitised: shapes, states, version numbers
and relative timings. Real gateway IDs, device addresses, hostnames, tokens and
certificates stay in private operator storage. Sanitisation is a manual, reviewed step —
raw output is not copied into this repository automatically.

Evidence is also labelled by how it was produced, and the three are never mixed:

| Label | Means |
|---|---|
| `ci` | Produced by automated checks with no hardware involved |
| `simulated` | Produced against a simulator or a dry run |
| `hardware` | Produced on physical gateways and physical devices |

A green CI run is not hardware qualification, and this repository does not present it as
one.
