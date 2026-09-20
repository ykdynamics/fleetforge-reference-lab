# What the lab found in the product

A reference lab exists to be run, and running it produces findings. These are recorded
here so the lab's own claims stay auditable, and so a reader can see what kind of thing
this exercise catches.

All three were found on physical hardware. None was visible from reading code or from a
green test suite.

## Z-Wave device operation was impossible — fixed

**[fleetforge#415](https://github.com/ykdynamics/fleetforge/issues/415) · fixed and
verified on hardware**

Operating a Z-Wave device through FleetForge could not work. The agent's broker allowlist
was built from the Zigbee2MQTT address and the generic MQTT address, and the Z-Wave JS
address was not among them — so on a Z-Wave-only gateway the allowlist was empty. A
request naming no broker resolved to nothing; one naming the correct local broker was
rejected as a broker the agent is not configured for.

**It failed silently on every FleetForge-side signal.** The capability run succeeded, the
agent polled the command and logged that it had handled it, and nothing was published and
the device never moved. Only looking at the lamp could tell the difference.

Fixed by adding that one configured address, with tests that fail without it. Re-verified
here: the lamp went dark and lit again, human-observed.

**Why it survived until now:** a Zigbee lamp was already switching through FleetForge,
with receipts. Had that been read as evidence for both protocols — which is exactly what a
demonstration is tempted to do — the gap would have shipped as a working feature.

## Actuation makes the caller build protocol topics — open

**[fleetforge#417](https://github.com/ykdynamics/fleetforge/issues/417) · design, open**

To switch a lamp the caller hands `mqtt.publish` a topic string and a payload, so it must
know that Zigbee addresses devices by IEEE address on a `/set` topic with a state string,
while Z-Wave addresses them by node, command class, endpoint and property with a boolean.

FleetForge already holds the device, its protocol, its external id and its observing
gateway — the collector parsed those very topics. Then actuation asks the caller to
reconstruct by hand what the product already parsed.

Consequence: **nothing validates the topic.** A wrong node, a wrong command class or a
read-only property produces `queued: true`, a `succeeded` run, an agent log line saying
the command was handled, and silence. That is the same failure shape as #415.

## A gateway that has run commands cannot be deleted — open

**[fleetforge#418](https://github.com/ykdynamics/fleetforge/issues/418) · open**

Rebuilding a gateway leaves a stale record, which the documentation says to retire
deliberately. Archiving works; deleting fails on a foreign key from `commands`, so any
gateway that has ever executed a command is permanently undeletable.

The status code is the more dangerous half: the failure is reported as `unavailable`
(HTTP 503), whose meaning here is *ask again*. It is a permanent constraint violation, so
a client implementing retry-on-503 — the correct behaviour for a real 503 — loops forever.

## Metering freshness is not a property of a device

**No product issue — a lab finding about what any consumer should assume**

Two plugs, two protocols, two observation models:

- The Zigbee plug reports roughly every ten seconds whether or not anything changed.
- The Z-Wave plug reports **on change only**. A 95-second subscription to its whole topic
  tree received 55 messages and **not one new measurement** — all retained values
  republished at subscribe time.

And within a single payload, fields differ: the Zigbee plug's `power` and `current` varied
report to report while `voltage` stayed frozen until explicitly read.

So a freshness expectation calibrated on one device, one protocol or one field is wrong
for the others. Judge age, not arrival — which is why
[`make radio-devices`](../README.md) reports `measured Nm ago` where the payload carries a
timestamp, and `UNKNOWN` where it cannot tell a constant value from a cached one.
