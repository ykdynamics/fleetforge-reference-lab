# Operator command contract

The complete operator surface this lab intends to expose, agreed **before** it is built so
that later work packages extend a shape rather than invent one per chapter.

> **Nothing in the "planned" tables below is implemented.** These are proposed target
> names and behaviours. This repository does not ship targets that exit `0` while doing
> nothing — a target appears in the Makefile when it does the work described here, and not
> before. Run `make help` to see what actually exists.

## Implemented today

| Target | Reads/Mutates | What it does |
|---|---|---|
| `make help` | reads | Lists the targets that actually exist |
| `make check` | reads | Runs both checks below |
| `make check-links` | reads | Validates every relative Markdown link resolves to a file |
| `make check-examples` | reads | Parses every `*.example.yml` as YAML |

`make check` exits non-zero on the first failing check and prints the offending file and
line. It touches no host and no network.

## Conventions every target follows

**Selection is explicit for anything that mutates.** There is no default `HOST`, no "all
hosts" mode and no target that discovers what to act on. A mutating target with a missing
or ambiguous `HOST` fails with exit code `2` and a message naming what was missing. The
lab never guesses which lamp to switch.

**Read-only targets are safe to run at any time**, including against a production-ish
estate you care about. They do not start, stop, configure or reset anything, and they
never print secrets, radio keys, tokens or enrollment file contents.

**Destructive targets need a matching confirmation.** `CONFIRM=` must equal the `HOST`
value. A mismatch is `FAIL`, exit `2`, before anything happens. This makes "wrong window,
right command" much harder.

**Exit codes are uniform:**

| Code | Meaning |
|---|---|
| `0` | The target did what it says, and every check it made was `PASS` or `WARN` |
| `1` | A check reported `FAIL`, or the underlying command failed |
| `2` | Usage error: missing/invalid argument, or a confirmation mismatch. Nothing was attempted |

**Errors are preserved, not summarised.** Shell helpers run under `set -eu`, do not pipe
failures into `|| true`, and surface the underlying command's own message and status. A
step that cannot determine something reports `UNKNOWN` — never a cheerful default. See
[Evidence conventions](evidence-conventions.md).

**Shared arguments:**

| Argument | Meaning |
|---|---|
| `HOST=` | The inventory alias of one gateway. Never an IP address in a documented example |
| `ROLE=` | `zigbee` or `zwave`. Validated against the inventory; a mismatch is `FAIL` |
| `DEVICE=` | The device to act on, by its inventory alias. Required for every device mutation |
| `INVENTORY=` | Path to your private inventory file. No default that points inside this repository |
| `CONFIRM=` | Must equal `HOST` for destructive targets |

---

## Planned — WP-02: provisioning and inspection

| Target | Args | Reads/Mutates | Prerequisites | Expected output | On failure |
|---|---|---|---|---|---|
| `preflight` | `HOST` `ROLE` | reads | SSH reachable | PASS/WARN/FAIL/UNKNOWN lines for OS and architecture, sudo, disk headroom, radio adapter identity from a stable by-id path, and whether a lab stack is already installed | `FAIL` per unmet prerequisite, each naming the fix. Exit `1` |
| `provision-plan` | `HOST` `ROLE` | reads | `preflight` clean | The diff provisioning *would* apply — packages, directories, permissions, units. Changes nothing | Exit `1` if the plan cannot be computed |
| `provision` | `HOST` `ROLE` | **mutates** | `provision-plan` reviewed | Applies the plan. Reports whether this was a fresh setup or adoption of an existing host. Re-running is idempotent and preserves data | Stops at the failing task with Ansible's own error. Never partially rewrites host networking |
| `host-info` | `HOST` | reads | SSH reachable | Kernel, architecture, disk, Docker version, radio adapters by-id, installed lab components. No secrets | Exit `1` if unreachable |

`provision` never modifies host networking, never overwrites an existing protocol stack
without reporting it first, and binds services to addresses taken from the inventory —
defaulting to loopback, so nothing is exposed to a wider network by accident.

## Planned — WP-03: the standalone estate

| Target | Args | Reads/Mutates | Prerequisites | Expected output | On failure |
|---|---|---|---|---|---|
| `stack-config` | `HOST` `ROLE` | reads | provisioned | Renders and validates the Compose configuration. Changes nothing | Exit `1` with the validation error |
| `stack-up` | `HOST` `ROLE` | **mutates** | `stack-config` passes | Starts the broker and the role's protocol service, then prints service status | Exit `1`; leaves already-running services alone |
| `stack-down` | `HOST` `ROLE` | **mutates** | — | Stops the role's services. **Keeps all volumes and pairings** | Exit `1` |
| `stack-status` | `HOST` `ROLE` | reads | — | Per-service state, bounded-logging settings actually in effect, broker reachability, disk headroom | Exit `1` on `FAIL` |
| `stack-logs` | `HOST` `ROLE` | reads | — | Tails the role's service logs | Exit `1` |
| `radio-devices` | `HOST` `ROLE` | reads | stack up | Devices the protocol service holds, with identity and last-seen. Service health is reported **separately** from device responsiveness | `UNKNOWN` where the service cannot be queried |
| `radio-join-open` | `HOST` `ROLE` `MINUTES` | **mutates** | stack up | Opens pairing/inclusion on **this gateway only**, for a bounded window, and reports the closing time | Exit `1`. Never opens joining on more than the named host |
| `radio-join-close` | `HOST` `ROLE` | **mutates** | — | Closes pairing/inclusion. Safe to run when already closed | Exit `1` |
| `lamp-off` / `lamp-on` | `HOST` `ROLE` `DEVICE` | **mutates** | device paired | Switches the lamp **through the protocol service**, then reports what the device reported back and prompts for a human observation | Exit `1`. Does not retry automatically |
| `radio-backup` | `HOST` `ROLE` `BACKUP_DIR` `[DRY_RUN=1]` | reads host, writes locally | stack present | Archives protocol persistent state to a private path with a checksum manifest. Excludes agent enrollment state and secrets. Never prints key material | Exit `2` without `BACKUP_DIR`; exit `1` on archive failure |

Pairing and inclusion remain **manual and physical** in this lab: you put the device into
its join mode yourself. `radio-join-open` only opens the window, and only on the one
gateway you named — with several coordinators in one room, a device being reset will join
whichever one is listening.

## Planned — WP-04: FleetForge integration

| Target | Args | Reads/Mutates | Prerequisites | Expected output | On failure |
|---|---|---|---|---|---|
| `ff-access-check` | `INVENTORY` | reads | [Software access](software-access.md) satisfied | Confirms the operator endpoint answers, credentials authenticate, the CA file referenced by the inventory exists and is readable, and the agent artifact is obtainable | Exit `1` naming which of the four is missing. Distinguishes "no access" from "wrong URL" |
| `agent-plan` | `HOST` `ROLE` | reads | `ff-access-check` passes | What installing the agent would change, and **whether this host is already enrolled** | Exit `1` |
| `agent-install` | `HOST` `ROLE` `TOKEN_FILE` `[CA_FILE]` | **mutates** | `agent-plan` reviewed | Installs and starts the agent with the role's collector pointed at the local broker. **Preserves existing enrollment identity** — a re-run upgrades in place and the gateway keeps its identity. The token is read from a file, never an argument, and is not logged | Exit `2` if the token file is missing/unreadable; exit `1` on install failure. Never silently re-enrolls |
| `agent-enroll-fresh` | `HOST` `ROLE` `TOKEN_FILE` `CONFIRM=HOST` | **mutates** | deliberate decision | **Discards existing enrollment identity** and enrolls as a new gateway. The old gateway record is left behind in the control plane for you to retire | Exit `2` on confirmation mismatch |
| `agent-status` | `HOST` | reads | — | Agent version, service state, last cycle result, and the **non-secret** collector settings in effect | Exit `1` |
| `ff-gateway` | `HOST` | reads | access | The control plane's view of this gateway: identity, last heartbeat, agent version | `UNKNOWN` if the gateway is not found |
| `ff-devices` | `[HOST]` | reads | access | Devices as the control plane sees them, attributed to the observing gateway, with observation timestamps | Exit `1` |
| `ff-health` | `HOST` `ROLE` | reads | access | Four results kept separate: host/radio service health, agent authentication and heartbeat, device observations received, and field freshness | Exit `1` on `FAIL`; `UNKNOWN` where not measurable |

`agent-install` being safely repeatable is a hard requirement: re-running integration must
not mint a second gateway record for the same physical host. Fresh enrollment is a
different target with a different name and its own confirmation, because it is a different
decision.

## Planned — WP-05: operating through FleetForge

| Target | Args | Reads/Mutates | Prerequisites | Expected output | On failure |
|---|---|---|---|---|---|
| `ff-lamp-off` / `ff-lamp-on` | `HOST` `DEVICE` `KEY` | **mutates** | enrolled; restoration prepared | Submits the operation **through FleetForge's own interface** with the caller-supplied idempotency key, and prints the run and command identifiers plus their states. Output says `queued`, not `switched` | Exit `1`. **Does not resubmit.** On a timeout it prints the key and tells you to re-run the identical command |
| `ff-run` | `RUN` | reads | access | One operation's state, timing, attempts and output | `UNKNOWN` if not found |
| `ff-command` | `COMMAND` | reads | access | The gateway command's state and delivery timing | `UNKNOWN` if not found |
| `ff-observe` | `DEVICE` | reads | access | What the device reports now, with timestamps, and freshness classified as reported / missing / stale / unknown. Zero readings are shown as zeros | Exit `1` |
| `ff-exercise-record` | `HOST` `DEVICE` `OUTCOME` `WITNESS` | writes locally | an exercise was run | Appends one outcome record in the [agreed shape](evidence-conventions.md#recording-an-outcome). `WITNESS` is `automated`, `device-reported` or `human-observed`; `OUTCOME` may be `UNKNOWN` and frequently should be | Exit `2` on an unrecognised witness or outcome |
| `evidence-bundle` | `OUT` | reads, writes locally | — | Collects versions, states and sanitised results into one directory for review **before** any publication | Exit `1` |

Retries follow the product's idempotency contract, described in
[Evidence conventions § Retries and idempotency](evidence-conventions.md#retries-and-idempotency).
No target ever retries a physical switch on its own initiative.

## Planned — WP-06: restoration and reset

Four separate operations, deliberately not one flag on one target. They destroy different
things, and conflating them is how somebody wipes a radio network while meaning to restart
an agent.

| Target | Args | Destroys | Keeps | Confirmation |
|---|---|---|---|---|
| `scenario-restore` | `HOST` `ROLE` `DEVICE` | Nothing | Everything | None — it only returns the lamp to its documented baseline state |
| `agent-remove` | `HOST` `CONFIRM=HOST` | The agent service and its configuration | Radio stack, pairings, protocol data, **and the enrollment identity file** unless `PURGE_IDENTITY=1` | `CONFIRM=HOST` |
| `protocol-data-reset` | `HOST` `ROLE` `CONFIRM=HOST` | The protocol service's persistent data — **this destroys the radio network and every pairing on this gateway** | The host, Docker, the agent and its identity | `CONFIRM=HOST` |
| `host-reset` | `HOST` `CONFIRM=HOST` | Everything this lab installed **on the named host**: agent, identity, stacks, volumes, lab directories | The OS and your SSH access | `CONFIRM=HOST` |

Rules these targets obey:

- **One host at a time.** No target accepts a list, and none has an "all" mode. There is no
  path to an implicit estate-wide wipe.
- **The control plane is never reset from here.** Retiring a stale gateway record is done
  through FleetForge's own interface, deliberately, by you.
- **Effects on pairing and identity are printed before the destructive step**, naming what
  will be lost, and the step is refused if the confirmation does not match.
- **`agent-remove` keeps the identity file by default.** Removing the agent to reinstall it
  should not cost the gateway its identity; discarding identity is opt-in.
- **Recovering pairings after `protocol-data-reset` means physically re-pairing every
  device.** A backup restores protocol *state*; some radio adapters hold network identity
  in the adapter itself. The target reports the adapter-specific limit rather than
  promising universal restoration.

## Not offered

- A target that acts on every host at once
- A target that resets the control plane or another tenant's data
- A generic remote-shell target
- Any target that retries a physical device operation automatically
- A "verify" target that reports `PASS` for something it did not measure
