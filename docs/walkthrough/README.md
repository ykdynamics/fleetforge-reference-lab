# The walkthrough

One continuous path: build a small IoT estate, feel what is missing, add FleetForge to the
estate you already have, operate it, and then put it back.

Read the chapters in order. Each one states what it assumes, what you do, what you should
see, and what commonly goes wrong.

| # | Chapter | Status |
|---|---|---|
| 1 | [Prerequisites and hardware](01-prerequisites.md) | **Usable now** |
| 2 | [The standalone estate](02-standalone-estate.md) | Structure and concepts now; commands planned (WP-02, WP-03) |
| 3 | [FleetForge integration](03-fleetforge-integration.md) | Structure and concepts now; commands planned (WP-04) |
| 4 | [Operation and evidence](04-operation-and-evidence.md) | Structure and concepts now; commands planned (WP-05) |
| 5 | [Reset and repeat](05-reset-and-repeat.md) | Structure and concepts now; commands planned (WP-06) |

## How to read the status labels

This repository is being built in public, and the guide exists before all of the
automation does.

> **Planned (WP-0X).** The step is designed and agreed, but not implemented. Command names
> shown under a planned label are **proposals** from the
> [command contract](../command-contract.md), and running them today will simply tell you
> the target does not exist.

Anything **not** marked planned is runnable now. Chapter 1 and the
[Pi imaging notes](../raspberry-pi-image.md) are entirely standard OS work and do not
depend on this repository's automation at all.

## Before you start

Two pages are worth reading first, because both can change whether the lab is feasible for
you this week:

- **[Software access](../software-access.md)** — chapters 3 to 5 need FleetForge
  control-plane access and agent artifacts, neither of which is public.
- **[Architecture and scope](../architecture-and-scope.md)** — what the pieces are, and
  what this lab deliberately does not do.

## One role or two

Either gateway role is a complete lab. If you have one Pi and one radio, build that role
and work through every chapter with it.

The second role earns its place in chapters 3 and 4, where it demonstrates something the
first cannot: that a control path proven on one protocol is **not** evidence for the
other. If you are buying hardware for this lab and can only buy one set, start with
whichever protocol you already have devices for.
