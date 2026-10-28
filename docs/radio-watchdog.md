# Radio watchdog (Zigbee gateways)

A systemd timer on a Zigbee gateway that restarts Zigbee2MQTT, or power-cycles the
coordinator, when the radio path stops working. It exists because of two failures seen
on the lab's Zigbee gateway between 2026-10-23 and 2026-10-28. Neither one shows up as an error.

## What it recovers from

1. **The adapter drops off USB and comes back.** The kernel logged `USB disconnect`, and
   the dongle re-enumerated 17 s later. Zigbee2MQTT stopped with `Adapter disconnected`
   (exit 2). Docker's `unless-stopped` restart ran one second later, while
   `/dev/serial/by-id/…` was still missing, and failed with "error gathering device
   information". Docker never tried again, so Zigbee2MQTT stayed down for 11 hours.
2. **The coordinator stops passing radio traffic.** The USB link stays up and
   Zigbee2MQTT reports itself online, but no device message arrives. The mains plug,
   which normally reports every 10 s, went quiet, and reads to it timed out. This lasted
   five days. Restarting the container did **not** clear it; a power cycle did (a reboot
   at the time). The coordinator ran Z-Stack `20210708`, and old Z-Stack firmware is
   known to hang like this. Updating the coordinator firmware is the root fix, a separate
   decision.

## What a check does

Every minute after the previous check (`ff-lab-radio-watchdog.timer`):

| Situation | Action |
|---|---|
| Adapter path absent | Nothing: the kernel has not re-enumerated it yet |
| Container exited non-zero (2 = adapter lost), adapter present | `docker start ff-lab-zigbee2mqtt` |
| Container stopped cleanly (exit 0) | Nothing: a deliberate stop (`radio-backup`, `radio-adapter-reset`, `reset` all use `docker compose stop`) |
| Container absent (`make stack-down` removes it) | Nothing |
| Broker not running | Nothing: silence cannot be judged without it |
| A fresh device message within `SILENCE_S` (default 300 s) | Nothing: healthy; the recovery record is cleared |
| No device message within `SILENCE_S` | Stop Zigbee2MQTT, cut USB power (`uhubctl`, both hubs on a Pi 4), wait 5 s, restore it, wait for the adapter, start Zigbee2MQTT |
| Still silent, inside `COOLDOWN_S` (default 3600 s) of that | Nothing, logged; one power cycle per hour at most |
| Still silent after a power cycle, `radio_watchdog_reboot: true` | Reboot, at most every 12 h (off by default) |

Silence counts only **non-retained** messages on `zigbee2mqtt/<device>` (`mosquitto_sub -R`).
That way, the broker replaying the last state of every device on connect doesn't count as
traffic.

**Do not install it on a gateway without a device that reports on its own.** Sleepy battery
sensors can be quiet for hours, and the watchdog would power-cycle that gateway every hour.
The lab's Zigbee gateway has the S60ZBTPF plug, which reports every 10 s.

Cutting USB power on a Raspberry Pi 4 drops **every** USB port, because the ports are
ganged. The lab's Zigbee gateway boots from its SD card and has nothing on USB but the coordinator. Do
not enable it on a host that boots from, or depends on, another USB device.

## Commands

```sh
make test-radio-watchdog                                   # simulated: every decision above, fake tools
make radio-watchdog-install HOST=lab-gw-zigbee ROLE=zigbee     # uhubctl, script, settings, timer; ends with a dry run
make radio-watchdog-dry-run HOST=lab-gw-zigbee ROLE=zigbee     # what a check would do now
make radio-watchdog-status  HOST=lab-gw-zigbee ROLE=zigbee     # timer, last checks, last recovery
make radio-watchdog-force   HOST=lab-gw-zigbee ROLE=zigbee     # power-cycle now: the hardware test
```

Installing touches neither the protocol stack nor its data: no Compose file is placed and
no container is recreated. Inventory settings, all optional: `radio_watchdog_silence_s`,
`radio_watchdog_cooldown_s`, `radio_watchdog_usb_hubs` (default `1-1 2`, for a Pi 4),
`radio_watchdog_reboot` (default `false`) and `radio_watchdog_reboot_cooldown_s`.

On the gateway: the script is `/usr/local/lib/ff-lab/radio-watchdog.sh`, the settings are
in `/etc/ff-lab/radio-watchdog.env`, the recovery record is in
`/var/lib/ff-lab-radio-watchdog/`, and the log is `journalctl -u ff-lab-radio-watchdog`.

## Evidence

`make test-radio-watchdog` is simulated: it shows which action each situation leads to.
That a USB power cycle clears a hung coordinator has to be shown on the gateway. Run
`make radio-watchdog-force`, then check that devices report again (`make radio-devices`, or
the door sensor). Record the result in an evidence note.
