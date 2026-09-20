# Inventory

Your inventory describes **your** gateways: where they are, what radio each one has, and
where its local services listen. Every lab command reads it.

It is deliberately small. This is a lab with at most two hosts — a configuration framework
would be more work to understand than the thing it configures.

## Getting started

```sh
cp inventory/inventory.example.yml inventory/inventory.yml
$EDITOR inventory/inventory.yml
```

`inventory/inventory.yml` is git-ignored. So is `inventory/group_vars/*.yml`, apart from
the `*.example.yml` files. You can also keep your inventory entirely outside this
repository and pass `INVENTORY=<path>`.

**Delete the group you are not building.** Either role runs alone, and a half-filled group
for hardware you do not own only produces confusing failures.

## Two rules

**1. No secrets in the inventory.** Tokens, API keys, certificates and radio network keys
are referenced by **path to a file you hold privately**, never by value. Those files live
outside this repository with restrictive permissions:

```sh
mkdir -p ~/.config/fleetforge-lab && chmod 700 ~/.config/fleetforge-lab
# put token / key / CA files here, then:
chmod 600 ~/.config/fleetforge-lab/*
```

The lab reads secrets from files rather than accepting them as command arguments, because
arguments are visible in process listings and end up in shell history and logs.

**2. No real identifiers in anything you contribute back.** The example file uses
documentation addresses (RFC 5737), `.example` hostnames and obviously fictional adapter
strings. Keep it that way.

## Fields

### Per host

| Field | Meaning |
|---|---|
| `ansible_host` | However you already reach the Pi — a hostname, an SSH config alias, or an address. The lab assumes no fixed subnet and never rewrites host networking |
| `role` | `zigbee` or `zwave`. Selects the protocol service and the agent's collector |
| `radio_adapter` | **A `/dev/serial/by-id/...` path.** See below |
| `radio_adapter_driver` | Zigbee only: which adapter driver Zigbee2MQTT should use |
| `mqtt_endpoint` | Where the local broker listens. The protocol service publishes here and the agent's collector reads from here |
| `protocol_ui_port` | The protocol service's own web UI port |
| `enrollment_token_file` | Path to this gateway's one-time registration token |
| `devices` | The devices the lab operates on this gateway |

### Per device

| Field | Meaning |
|---|---|
| `alias` | What you pass as `DEVICE=`. Every mutation names its target explicitly |
| `kind` | `wallplug` for the lamp exercise |
| `protocol_ref` | How the protocol service addresses it. Filled in after pairing |
| `metering` | Whether it reports power/current/energy. Leave `unknown` until you have actually looked — metering is optional and the lamp exercise never requires it |

### Shared

| Field | Meaning |
|---|---|
| `ansible_user` | The account the lab connects as. Needs sudo; key-based SSH only |
| `lab_root` | Where the lab installs things on each gateway |
| `lab_bind_address` | What the broker and UIs bind to. Defaults to loopback |
| `fleetforge.operator_url` | The UI and operator API |
| `fleetforge.agent_plane_url` | Where gateways enrol and poll — a **different** listener |
| `fleetforge.ca_file` | Path to pinned CA trust material |
| `fleetforge.api_key_file` | Path to your operator API key |

Delete the whole `fleetforge` block to run the standalone lab only.

## Always use a by-id adapter path

```sh
ls -l /dev/serial/by-id/
```

`/dev/ttyUSB0` and `/dev/ttyACM0` are assigned in enumeration order and can change across a
reboot or a replug. A service pointed at the wrong stick fails in ways that look like a
broken mesh rather than a wrong path — and with two gateways in one room, that is a
genuinely confusing hour.

## Bind addresses

`lab_bind_address` defaults to `127.0.0.1`. A broker reachable from a wider network is a
broker anyone on that network can publish to — and this one drives a physical relay.

To reach a protocol UI from your workstation without widening the bind address, forward the
port over SSH:

```sh
ssh -L 8099:127.0.0.1:8099 labops@<your host>
```

Widen the bind only deliberately, knowing what else is on that network, and never to
`0.0.0.0` on one you do not control.

## What git ignores

Checked in: `*.example.yml` only. Ignored: your real inventory, your real group vars,
anything under a `secrets/` directory, key and certificate files, and collected evidence.
See [`.gitignore`](../.gitignore) — and check before you commit:

```sh
git status --short
git check-ignore -v inventory/inventory.yml
```
