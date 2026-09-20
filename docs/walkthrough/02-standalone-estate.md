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

## 2.2 Provision the host — planned (WP-02)

> **Planned.** Proposed targets, not implemented.
>
> ```text
> make provision-plan HOST=<alias> ROLE=zigbee|zwave     # read-only: shows the diff
> make provision      HOST=<alias> ROLE=zigbee|zwave     # applies it
> ```

Ansible installs the packages, directories, permissions and service configuration the role
needs. It is idempotent: re-running preserves data, and it reports whether it performed a
fresh setup or adopted a host that already had a stack.

It does **not** modify host networking, and it does not silently overwrite an existing
protocol stack.

It also handles the two Ubuntu services that claim USB serial adapters — `brltty` and
`ModemManager` — which between them make a working radio look like dead hardware. See
[Imaging a gateway Pi](../gateway-os-image.md#two-services-that-steal-usb-serial-adapters).

## 2.3 Start the protocol stack — planned (WP-03)

> **Planned.** Proposed targets, not implemented.
>
> ```text
> make stack-config HOST=<alias> ROLE=<role>    # read-only: validates the configuration
> make stack-up     HOST=<alias> ROLE=<role>
> make stack-status HOST=<alias> ROLE=<role>
> ```

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

> **Planned.** The window-opening targets are proposed, not implemented.
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

## 2.5 Switch the lamp from the protocol UI — planned (WP-03)

The baseline exercise. From the protocol service's own interface, switch the wallplug off,
confirm the lamp goes dark, switch it on, and confirm it lights.

> **Planned.** Proposed targets for the same exercise from the command line.
>
> ```text
> make lamp-off HOST=<alias> ROLE=<role> DEVICE=<alias>
> make lamp-on  HOST=<alias> ROLE=<role> DEVICE=<alias>
> ```

Record the result in the [agreed shape](../evidence-conventions.md#recording-an-outcome),
and note which fields the device actually exposes: what is writable, what it reports back,
and on which channel. If it reports power or current, note whether the numbers move when
the lamp is lit — and **record a zero as a zero** if that is what you see. Metering is
optional here and several plugs report nothing useful.

**Restore the lamp to lit before moving on.** The estate should start chapter 3 in a known
state.

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
