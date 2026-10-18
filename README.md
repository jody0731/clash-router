# Clash Router

Clash (mihomo, through [Nikki](https://github.com/nikkinikki-org/OpenWrt-nikki)) on a home router: an
**H3C TX1801 Plus** (China Telecom edition, MT7621 + MT7915) flashed with **OpenWrt 25.12.5**. Every device on the
router's own Wi-Fi gets Clash without an app. China traffic skips Clash and runs at line speed.

The whole procedure, from the serial cable to the day-to-day running, is in **[RUNBOOK.md](RUNBOOK.md)**. It's
written to be followed offline, because a mistake here can leave you without internet.

## What's here

| File | What it is |
|---|---|
| `RUNBOOK.md` | Lifelines, phases 0–4 (prepare, flash, plain router, Clash, a PC onto the router), living with it, emergencies |
| `push-union.py` | Renders a Clash profile template with its subscription links (never printed), checks it on the router with `mihomo -t`, installs it and restarts Nikki |
| `router/stall-watcher.uc`, `deploy-watcher.sh` | A ucode service on the router that spots a node stalling after the first few KB (which mihomo's HEAD health checks miss), confirms it with one probe page and moves the fallback group to the next node in the same country; tested by 7 scenarios before every install |
| `docs/img/` | Where the serial header is (J4) and how the board looks with the cover off |

Not included, on purpose: the backup of the router's original firmware (it holds the device's own data), the
OpenWrt and Nikki downloads (get them from [OpenWrt](https://firmware-selector.openwrt.org/) and Nikki's releases),
and any subscription link.

## What we learned

- **Flashing:** serial console on J4, U-Boot's `=>` prompt (tap `0`), TFTP an initramfs, back up every `mtd`
  partition, then `fw_setenv bootflag 0` and `sysupgrade`. In 25.12, `uci set network.lan.ipaddr` needs `/24`, or
  the address ends up `/32` and the router becomes unreachable.
- **This unit's 2.4 GHz radio was dead** (hardware, already silent on the stock firmware), so the router runs 5 GHz
  only, on channel 149 to stay off radar channels.
- **China bypass at full speed:** Nikki's `bypass_china_mainland_ip`, plus a fake-IP filter of `geosite:cn` so China
  domains resolve to real addresses. A China mirror ran at 112 MB/s with flow offloading, the router's CPU 95 % idle.
- **The loop bug:** with "router proxy" on, the router caught mihomo's own connections to foreign node servers and
  fed them back into mihomo. Set `router_proxy=0`.
- **The limit:** the MT7621 encrypts slowly. Foreign traffic through the router's Clash reaches about 12–30 Mbps,
  against 100+ Mbps through Clash on a desktop PC. Fine for phones; a PC that wants speed keeps its own Clash.

## Clash rules this setup keeps

Sticky single-country `fallback` groups only: no `url-test`, no load balancing, no groups spanning countries.
Exit-IP hopping gets accounts flagged by websites.

## License

MIT, see [LICENSE](LICENSE).

## Use at your own risk

Flashing can brick a router, and its warranty is gone. Keep the original firmware backup off the router, and make
sure you have a second way online before you start (the runbook's lifelines).
