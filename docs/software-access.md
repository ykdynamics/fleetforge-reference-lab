# Software access

**Read this before chapter 3.** The standalone half of this lab uses only open-source
software you can install today. The FleetForge half does not.

This repository being public says nothing about FleetForge being public.

## What you need, and where it comes from

| Component | Source | Public? |
|---|---|---|
| Raspberry Pi OS Lite (64-bit) | raspberrypi.com | Yes |
| Docker Engine + Compose plugin | docker.com | Yes |
| MQTT broker (Mosquitto) | Docker Hub | Yes |
| Zigbee2MQTT | Docker Hub | Yes |
| Z-Wave JS UI | Docker Hub | Yes |
| Ansible | your package manager / PyPI | Yes |
| **A FleetForge control plane** | You deploy one, or you are given access to one | **No** |
| **The FleetForge agent artifact** | Distributed by the FleetForge maintainers | **No** |

## The two things you must obtain separately

### 1. Control-plane access

There is no public hosted FleetForge instance offered by this repository, and this
repository does not embed anyone's deployment. You need **one** of:

- a FleetForge control plane you deploy yourself, which requires access to the
  (currently private) product repository or its deployment artifacts; or
- credentials for an instance somebody else runs.

Either way you need, before chapter 3 will work:

- **The operator base URL** — where the UI and the operator API live.
- **Operator credentials** — a sign-in identity for the UI, and an API key for API calls.
  Release builds seed **no** default credentials, and the zero-config development login is
  disabled unless explicitly enabled. If you were expecting a default password, there
  isn't one.
- **The agent plane endpoint** — gateways enrol and poll on a *different* listener from
  the one your browser uses. They are not interchangeable, and mixing them up fails in
  ways that read as an authentication problem.
- **CA trust material** — for a packaged agent enrolling over HTTPS, a pinned CA file is
  **required**. The release agent refuses first enrolment without it rather than trusting
  whatever answered. See [inventory/README.md](../inventory/README.md) for where that file
  is referenced from.
- **A registration token per gateway** — one-time, expiring, minted by an operator. It
  becomes a durable per-gateway identity at first enrolment; the token itself is not
  reusable and is not a long-lived credential.

### 2. The agent artifact

The agent is distributed as an OS package and as a container image. **Neither is
anonymously available.**

> Verified on 2026-09-20: an unauthenticated pull of the published agent container image
> from its registry is rejected (`403`). The image exists; access to it is gated.

So you need either:

- a package file supplied to you by the maintainers, or
- registry credentials that can read the agent image, applied on the gateway (a registry
  login) before any pull is attempted.

If a pull returns `unauthorized` or `denied`, that is this access requirement — not a
misconfigured gateway.

## If you do not have access

**Chapters 1 and 2 still work completely.** The standalone estate — provisioning, the
protocol stacks, pairing, and switching the lamp from the protocol UI — depends on nothing
private. That is a genuinely useful lab on its own, and it is where the problems this lab
is about actually become visible.

Chapters 3 to 5 are gated on the access above. This lab will say so at the point where it
matters rather than failing halfway through with a permission error.

## What this repository will never contain

No registration tokens, API keys, certificates, private keys, registry credentials or
control-plane addresses. Where a procedure needs one, the configuration references a
**path to a file you hold privately** — never a value. See
[inventory/README.md](../inventory/README.md).

A related consequence: secrets are never passed as command-line arguments in this lab,
because arguments are visible in process listings and tend to end up in shell history and
logs. They are read from files with restrictive permissions.

## Open question

Whether the agent artifacts will be made publicly pullable, or will stay gated with the
lab documenting a credentialed pull, is **undecided** and is tracked in
[Reuse audit § Open questions](reuse-audit.md#open-questions-for-the-repository-owner).
The answer changes how much of chapters 3 to 5 a stranger can complete.
