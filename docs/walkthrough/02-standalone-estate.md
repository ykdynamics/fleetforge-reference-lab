# 2. The standalone estate

Build a working IoT estate with no FleetForge in it at all, and switch a real lamp from a
protocol service's own web UI.

This chapter is not a warm-up. It is the "before" half of the comparison, and it has to
genuinely work — otherwise the rest of the lab is measuring against nothing.

**Assumes:** [chapter 1](01-prerequisites.md) complete, and a private inventory file.

## What gets installed

Per gateway, after provisioning:

```text
Raspberry Pi
├── Docker + Compose
├── MQTT broker            bound to loopback by default
├── protocol service       Zigbee2MQTT (Zigbee role) or Z-Wave JS UI (Z-Wave role)
│   └── persistent volume  the radio network, the pairings, the device database
└── USB radio adapter      addressed by its stable /dev/serial/by-id path
```

No FleetForge agent. Nothing reaching out. Everything on this Pi and nowhere else — which
is exactly the situation the second half of this lab is about.

## 2.1 Preflight — available now

```sh
make preflight HOST=<alias> ROLE=zigbee|zwave
```

A read-only check before anything is changed. It reports on the host baseline (OS,
architecture, Pi model, kernel), access (passwordless sudo), resources (disk headroom,
memory, a writable filesystem), the radio adapter at its by-id path, services that claim
USB serial adapters, any existing installation, and listener exposure.

It changes nothing, so it is safe to run repeatedly and safe to run on a host you care
about. Each line is `PASS`, `WARN`, `FAIL` or `UNKNOWN` — see
[Evidence conventions](../evidence-conventions.md). A `FAIL` names what is missing and how
to fix it. **Do not continue past one.**

Both the host and the role are explicit. If the role disagrees with your inventory the
command refuses rather than checking the wrong gateway — that is how you preflight the
Zigbee host and conclude the Z-Wave one is fine.

The three failures worth expecting on a fresh Ubuntu host:

| Reported | What to do |
|---|---|
| `FAIL privileges: sudo requires a password` | Provisioning is non-interactive and cannot answer a prompt. Give your account passwordless sudo |
| `WARN brltty is ...` / `WARN ModemManager is ...` | Both claim USB serial adapters and make a working radio look dead. Provisioning handles them; until then, expect adapter trouble |
| `FAIL configured adapter is missing` | Your inventory's `radio_adapter` does not match reality. Check it against `ls -l /dev/serial/by-id/` on the host |

An existing lab directory, an installed agent unit or an enrolment state file are reported
as `WARN`, not `FAIL`: they mean provisioning would **adopt** this host rather than set it
up fresh, which is a fact you should know before continuing, not an error.

## 2.2 Provision the host — available now

Look before you leap: the plan is read-only and shows exactly what would change.

```sh
make provision-plan HOST=<alias> ROLE=zigbee|zwave     # read-only: shows the diff
make provision      HOST=<alias> ROLE=zigbee|zwave     # applies it
```

Ansible masks the services that claim USB serial adapters, installs Docker and the Compose
plugin, sets host-wide container log bounds, and creates the lab directories.

It is idempotent: re-running preserves data, and the run reports whether it performed a
fresh setup or **adopted** a host that already had an installation. It does **not** modify
host networking, start a protocol service, install the FleetForge agent, or empty an
existing lab directory.

Docker is not upgraded on a re-run unless you ask for it (`docker_upgrade=true`). An
engine upgrade restarts the daemon, which stops every running container — not something a
"make sure this host is set up" command should do as a side effect.

**Log back in afterwards.** Adding your user to the `docker` group only affects new
sessions, so the first `docker` command in your existing SSH session will still be denied.

It also handles the two Ubuntu services that claim USB serial adapters — `brltty` and
`ModemManager` — which between them make a working radio look like dead hardware. See
[Imaging a gateway Pi](../gateway-os-image.md#two-services-that-steal-usb-serial-adapters).

## 2.3 Start the protocol stack — available now

```sh
make stack-config HOST=<alias> ROLE=<role>    # read-only: validates the configuration
make stack-up     HOST=<alias> ROLE=<role>
make stack-status HOST=<alias> ROLE=<role>
```

Compose brings up the broker and the role's protocol service, with persistent volumes and
bounded container logging.

**Bounded logging is not a detail.** A protocol service left logging without limits has
filled a gateway's root filesystem on real hardware, which stopped the broker — while the
host itself stayed up and looked healthy. Log limits are applied at creation; an existing
container has to be recreated to adopt them.

Once it is up, open the service's own web UI from your workstation — the address and port
come from your inventory. That UI is the standalone estate's entire management surface.

## 2.4 Pair the wallplug — manual, and staying that way

Pairing is **physical and manual** in this lab. At two devices, automating it would cost
more than it saves and would hide what is actually happening.

> **Planned (WP-03).** Targets for opening the window are proposed but not implemented;
> open it from the protocol service's own UI meanwhile. Pairing itself stays manual
> either way.
>
> ```text
> make radio-join-open  HOST=<alias> ROLE=<role> MINUTES=<n>
> make radio-join-close HOST=<alias> ROLE=<role>
> ```

The sequence, whichever way the window is opened:

1. Open the joining window **on the one gateway you are pairing to**.
2. Put the wallplug into its join mode — usually a button press pattern from its manual.
3. Watch the protocol service's UI for the device to appear and identify itself.
4. **Close the window.** Leaving it open is how devices end up on the wrong gateway.
5. Give the device a recognisable name, and record it in your inventory as the `DEVICE`
   alias the lab will use.

**If you are running both roles:** only ever open joining on one gateway at a time. A
device being reset joins whichever coordinator is listening, and landing a plug on the
wrong gateway is easy to do and easy not to notice until the fleet view looks wrong later.

Removing a device is the mirror image — unpairing on Zigbee, exclusion on Z-Wave — and is
worth doing once deliberately so you know how. A forced removal from the service side
leaves the device still believing it is joined until it is factory reset.

## 2.5 Switch the lamp from the protocol UI — available now

The baseline exercise. From the protocol service's own interface, switch the wallplug off,
confirm the lamp goes dark, switch it on, and confirm it lights.

The same exercise from the command line, which records the outcome for you:

```sh
make lamp-off HOST=<alias> ROLE=<role> DEVICE=<alias>
make lamp-on  HOST=<alias> ROLE=<role> DEVICE=<alias>
```

Run interactively it asks what you saw and records your answer as the witness. It never
reads success from the device's own echo.

Record the result in the [agreed shape](../evidence-conventions.md#recording-an-outcome),
and note which fields the device actually exposes: what is writable, what it reports back,
and on which channel. If it reports power or current, note whether the numbers move when
the lamp is lit — and **record a zero as a zero** if that is what you see. Metering is
optional here and several plugs report nothing useful.

### A worked example: why a lit lamp can report zero watts

This happened on the lab bench, and it is worth walking through because almost every step
of the obvious diagnosis is a trap.

A mains-metering Zigbee plug, lamp visibly lit, reporting `power: 0`, `current: 0`,
`energy: 0` — while `voltage` read a plausible 232.77 V. The device's own definition
advertised `power`, `current` and `voltage` as readable. So the readings were wrong, or
the plug was broken, or the reports were not arriving. All three turned out to be false.

**What the evidence actually showed, in order:**

| Observation | What it ruled out |
|---|---|
| A message every ~10s, with `linkquality` varying between them | Reports *were* arriving, live. Not a radio or reporting outage |
| `voltage` **bit-identical** at 232.77 across 75s and 10 updates | Live mains does not hold identical for 75 seconds. The periodic report was carrying a **cached** electrical value |
| An explicit read moved voltage to 234.68 | The metering block works and *can* produce a fresh value on demand |
| That same fresh read still returned `current: 0`, `power: 0` | The zero was not staleness. It was a genuinely fresh zero |

That left one hypothesis worth testing physically: the load was simply below what the plug
can resolve. Swapping the LED lamp for a slightly larger one settled it immediately —
`power` ≈ 9.8 W, `current` ≈ 0.07 A, both varying between reports. Nothing was broken. The
first lamp drew less than the plug could measure.

**Three things to take from it:**

1. **Message arrival and link quality say nothing about measurement freshness.** Both
   looked perfectly healthy while the electrical values were stale. This is exactly the
   separation [the evidence conventions](../evidence-conventions.md) insist on, and it is
   easy to believe you are looking at live power when you are looking at a cached number
   in a live message.
2. **Fields in one payload can have different freshness.** After the swap, `power` and
   `current` varied from report to report while `voltage` stayed frozen at a single value
   until explicitly read again. They arrive together and are not equally fresh. Do not
   treat one field's liveness as evidence for another's.
3. **A zero reading is a measurement, not a fault** — and not a licence to hide it. The
   correct display was always `0`, with its freshness marked unknown, until a physical
   fact settled what it meant.

**`energy` is a special case.** It is often report-only (`access: 1`) rather than
readable, so asking the device to read it returns a converter error — that is the device
definition being honest, not a failure. It also accumulates slowly: a ~10 W lamp needs
about four days to register the first `1 kWh`, so `energy: 0` is the expected reading for
any short exercise.

None of this is required for the lamp lesson. It is recorded because the wrong conclusion
was available at every step, and because a reader meeting a zero-watt lit lamp deserves
the diagnosis rather than the folklore.

**Restore the lamp to lit before moving on.** The estate should start chapter 3 in a known
state.

### Two recorded standalone outcomes

Both roles, run on the bench and written in the
[agreed shape](../evidence-conventions.md#recording-an-outcome). The Zigbee one first:

```text
what was asked   state → OFF, then → ON, on the paired plug, through the
                 protocol service's own MQTT interface
receipts         none — see below
device-reported  OFF leg: state OFF, power 9.24 W → 0
                 ON  leg: state ON, current 0.08 A
human-observed   operator reported the lamp went dark, then lit again
outcome          PASS — witness: human-observed
versions         Zigbee2MQTT 2.14.1 · Sonoff S60ZBTPF fw 8195
restoration      lamp returned to lit, confirmed by the operator
```

One detail in that record repays attention. Immediately after the ON leg the plug reported
`power=0` while `current=0.08` — not a contradiction, and not a fault. The plug reports
roughly every ten seconds, and the read landed before power had been re-measured while
current already had. **Two fields, one payload, different ages**, exactly as the metering
example above describes. A reader who took that `power=0` as "the lamp is drawing nothing"
would be wrong, and would have been wrong for about eight seconds.

And the Z-Wave exercise:

```text
what was asked   Binary Switch (CC 37) targetValue → false, then → true, on the
                 paired node, through the protocol service's own MQTT interface
receipts         none — see below
device-reported  currentValue false then true; Power 0 W then 16.6 W,
                 freshly timestamped in both directions
human-observed   operator reported the lamp went dark, then lit again
outcome          PASS — witness: human-observed
versions         Z-Wave JS UI 11.24.1 / zwave-js 15.29.0 · Fibaro FGWP-102 fw 3.2
restoration      lamp returned to lit, confirmed by the operator
```

Two things about that record are worth dwelling on.

**The outcome rests on the human observation, not the device report.** The plug reporting
`currentValue: false` after being told to switch off is closer to an echo than a
confirmation. It is recorded as `device-reported` and weighted accordingly. Had nobody
been watching, the correct outcome would have been `UNKNOWN` — every command succeeding
and nobody looking is a successful *request* and an unknown *result*.

**The `receipts` line is empty, and that is the point.** The standalone path produces
nothing you can audit tomorrow: no record of who switched it, when, or whether it worked.
The evidence above exists only because someone wrote it down by hand, immediately, while
watching. Scale that to fifty devices and it stops being possible. That gap — not the
switching, which works fine — is what [chapter 3](03-fleetforge-integration.md) is
about.

### The two protocols do not share a control model

Both roles were brought up on the bench, and the difference is the point of having two.

| | Zigbee (Sonoff S60ZBTPF) | Z-Wave (Fibaro FGWP-102) |
|---|---|---|
| Addressed by | friendly name / IEEE address | node id, command class, endpoint, property |
| Switched by | `state: "ON"` / `"OFF"` on the device's `/set` topic | Binary Switch (CC 37) `targetValue`, a boolean |
| Reads back as | `state` | Binary Switch (CC 37) `currentValue` |
| Power reported by | `power` in the device's state payload | Meter (CC 49) `Power` |
| Observation transport | MQTT, out of the box | **Not MQTT by default** — see below |

These are not the same recipe with different names. A Z-Wave switch is a command class and
a property on a node, not a string on a topic. That is why this lab refuses to treat a
control path proven on Zigbee as evidence for Z-Wave: the mapping had to be read off a
real interview, and it was.

Both plugs meter, and both reported live power that fell to zero when switched off and
rose again when switched on.

### Z-Wave JS UI does not publish to MQTT until you configure it

On the bench, with a Z-Wave plug included and responding, the gateway's broker carried
**zero messages** — not just no device topics, nothing at all. Z-Wave JS UI has an MQTT
gateway, and it is off until configured. Everything still works: the UI drives the plug,
the interview completes, values update.

This matters more than it looks. The standalone Z-Wave estate is perfectly usable over the
service's own UI and websocket, so nothing about it feels wrong. But anything that expects
to *observe* this gateway over MQTT will see an empty estate — a gateway that is up,
reporting nothing, with no error anywhere to explain it.

Configuring that gateway is a prerequisite for [chapter 3](03-fleetforge-integration.md),
where the agent's Z-Wave collector reads from this broker. It is tracked as part of that
work rather than papered over here.

Once it is on, control works in both directions: publishing to a value's `/set` topic
switched the plug, and the switch state and power both updated within seconds.

### The Z-Wave plug reports on change, not on a timer

Worth internalising before you trust any view of this estate.

With the plug included, responding, and its MQTT gateway configured, a 95-second
subscription to the whole Z-Wave topic tree received **55 messages and not one new
measurement**. Every one was a retained value republished the moment the subscription
opened. By message count the estate looked busy; nothing in it was current.

Switching the plug proved the values are not stuck. The moment the state changed, both the
switch state and the power reading updated within seconds:

```text
publish OFF   →  currentValue false   ·  Power 0      (both freshly timestamped)
publish ON    →  currentValue true    ·  Power 16.6   (both freshly timestamped)
```

So the device reports **on change**. While a lamp burns steadily it says nothing, and the
last reading ages quietly. Nothing is broken, and no amount of polling the broker produces
a newer number than the device has chosen to send.

The Zigbee plug on the other gateway behaves differently — it reports every ten seconds or
so whether or not anything changed. Two plugs, two protocols, two observation models. **A
freshness expectation calibrated on one is wrong for the other.**

Two consequences worth carrying into chapter 3:

- **Message arrival is not measurement freshness**, and here the gap is wide enough to
  matter: 55 messages, zero measurements. Anything that subscribes, sees traffic and
  concludes the estate is live would be wrong every time.
- **Judge age, not arrival.** Z-Wave payloads carry the time the value was recorded, so
  `make radio-devices` reports `measured Nm ago`. That is what exposed this — counting
  reports showed activity, the timestamp showed a sixteen-minute-old power figure.

If you want periodic reports instead of change-only, that is a configuration parameter on
the node, set through the protocol service. This lab leaves the device on its defaults and
reports the age instead, because the default is what most estates actually run.

## 2.6 Do it again for the second role — if you have one

Everything above, with the other role. Verify one role completely before starting the
other; two half-working gateways are much harder to debug than one working and one absent.

Record the exact adapter, device and service versions for each role in
[Hardware and versions](../hardware-and-versions.md). They are different stacks and they
get their own rows.

## What you should have noticed

This is the part of the chapter that matters, and it is why the standalone estate is built
rather than described:

- **There are two of everything.** Two UIs, two brokers, two device lists, and no single
  place to ask "is everything reporting?"
- **Nothing is written down.** You switched a lamp. There is no record of who did it, when,
  or whether it worked. Tomorrow you cannot audit it.
- **It only works from here.** Both UIs are reachable from your network and nowhere else.
- **Nothing tells you when a gateway goes quiet.** If a service dies overnight, the UI is
  simply unreachable — and only if you happen to look.
- **The two protocols are not interchangeable.** Different pairing, different addressing,
  different UIs, different device models. Everything you learned on one you partly relearn
  on the other.

None of these are faults of Zigbee2MQTT or Z-Wave JS. They are excellent at what they do.
They are single-site protocol services, and an estate is a different problem.

Next: [3. FleetForge integration](03-fleetforge-integration.md).
