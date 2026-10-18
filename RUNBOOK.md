# Clash Router runbook: Clash on the H3C TX1801 Plus

Working theory, local only (no GitHub). Written 2026-10-17 by Klaude. **Print this or put it on your phone before
flashing day**: if the router breaks, DT-26 may be offline and Klaude with it. Everything needed is in `offline/`.

## The goal

Flash our router (H3C TX1801 Plus, `192.168.3.1`) with OpenWrt and run Clash (Nikki = mihomo) with the Union config
on it, so every device on it gets Clash without its own app. The modem (`192.168.1.1`, China Telecom), router B and
the IPTV box are **not touched**.

```
modem ─ 2.5G/1G ─→ TX1801 Plus (OpenWrt + Nikki) ─→ DT-26 (wired) and Wi-Fi HOME-X-5G
      ─ 1G      ─→ router B (ZTE, unchanged)       ─→ Wi-Fi 202 / HOME-5G
      ─ iTV     ─→ IPTV box (unchanged)
```

## The Wi-Fi today (scanned from DT-26, 2026-10-17)

| Access point | Maker (from its MAC) | Broadcasts |
|---|---|---|
| Our router, TX1801 Plus (`192.168.3.1`) | H3C (`76:50:4E:…`) | `HOME` and `HOME-5G` per its settings, but only `HOME-5G` and a hidden network of its own were on the air (both 5 GHz, channel 36): its 2.4 GHz radio was already dead (found in Phase 2) |
| Router B | ZTE (`<router-B-MACs>`) | `HOME` and `HOME-5G`. It's an **access point on the modem's network**: devices on it get `192.168.1.x` from the modem. |
| A third one | ZTE (`EC:C3:B0:…`) | `HOME` and `HOME-5G` (probably the modem's own Wi-Fi, or a second ZTE unit) |

- **Neither ZTE depends on our router** (proven by the rehearsal, 2026-10-17). Our network (`192.168.3.x`) holds only our router, DT-26 and two other
  devices (a phone and an Intel Wi-Fi device): no ZTE is plugged into it. Flashing or unplugging our router
  leaves `HOME`/`HOME-5G` working; devices on our `HOME-5G` move to a ZTE by themselves (same name and password).
- **Why our router gets its own name** (`HOME-X-5G`; its 2.4 GHz radio is dead, see Phase 2): with one shared name, devices roam to
  whichever access point is strongest, so a phone would silently gain or lose Clash moving between rooms. With its
  own name, a device is on Clash exactly when it's on `HOME-X-5G`. Family devices, the TV and guests stay on `HOME`
  without Clash, as today.

## The one rule that keeps us safe

**Never cut the last road to the internet.** There are three, independent of the TX1801 Plus:

| Lifeline | How DT-26 gets online | Claude works because |
|---|---|---|
| L1: router B's Wi-Fi | DT-26's Wi-Fi (`wlp6s0`) is connected to `HOME-5G` and **pinned to router B** (`<router-B-BSSID>`); it stands by behind the cable. Rehearsed, works. | DT-26's own Clash Verge stays installed: turn its TUN on |
| L2: phone hotspot | Phone on mobile data, DT-26 joins its hotspot | same |
| L3: modem port | Unplug router B, plug DT-26 into that modem port | same |

So: **keep Clash Verge installed on DT-26**. Once DT-26 uses the router's Clash (Phase 4), Verge sits there
with TUN off, and turning TUN back on is the way back. And every
phase below ends in a working network, so stopping halfway is always safe.

## Phase 0: preparation (internet still normal)

1. ~~Buy~~ **Arrived 2026-10-17, works** (`/dev/ttyUSB0`, CH340 `1a86:7523`, through a USB 2.0 extension cable; TXD-RXD loopback at 115200 passed): Biaze (毕亚兹) CH340 USB-TTL adapter, JD item 100158018905, about ¥15, with jumper wires. Linux has
   the driver built in. **Set its switch to 3.3 V** before connecting.
   **No pins (checked from photos, 2026-10-17):** the serial port is **4 empty holes in a row**, and no
   extra parts are needed: the adapter plugs straight into them (Phase 1 step 4, Jody's idea).
   Where (close-up `docs/img/ttl-holes.png`): router upside down, ports at the far
   side with the blue WAN port on the right; **7th vent slot from the port edge, just left of the middle divider**
   (under LAN3).
2. ~~Rehearse L1~~ **Done 2026-10-17.** DT-26 joined `HOME-5G`, pinned to router B (it first picked our H3C, the
   strongest). With our router unplugged: China site, Google through Clash and Claude all worked over Wi-Fi.
   DT-26 got `192.168.1.221` from the modem, so Phase 1 never uses OpenWrt's default `192.168.1.1` (it's the
   modem's address too): the router's address is set over the serial cable instead.
   Undo the pin some day: `nmcli con mod HOME-5G 802-11-wireless.bssid ""`.
3. ~~Record the H3C settings~~ **Done 2026-10-17** (read by Klaude from the admin page): see "H3C settings
   before flashing" below. OpenWrt starts blank; that's what to re-create.
4. ~~Serial access~~ **Done 2026-10-17:** Jody is in the `dialout` group. (dnsmasq, already installed, is the
   TFTP server; `screen` is the serial terminal.)
5. **Already downloaded** (`offline/`, checksums verified 2026-10-17):
   - `tftp/initramfs.bin`: OpenWrt 25.12.5 initramfs for `h3c_tx1801-plus` (boots from RAM, writes nothing)
   - `openwrt-25.12.5-ramips-mt7621-h3c_tx1801-plus-squashfs-sysupgrade.bin`: the real install
   - `nikki_mipsel_24kc-openwrt-25.12.tar.gz`: Nikki v1.26.2 (mihomo + its web page) for this router
   - `openwrt-wiki-tx1801-plus.html`, `openwrt-commit-tx1801-plus.html`: the official instructions, offline
6. **Pick a time** (about 2 hours). The rest of the house stays online on the ZTEs' `HOME`/`HOME-5G` throughout.

## H3C settings before flashing (read 2026-10-17)

| Setting | H3C value | In OpenWrt |
|---|---|---|
| Model, firmware | H3C TX1801 Plus (China Telecom edition), `TX1801PCV100R006L02` | — |
| WAN | DHCP from the modem, MTU 1500, DNS automatic | WAN: DHCP (the default) |
| LAN | `192.168.3.1/24`, MAC `<LAN-MAC>` | LAN `192.168.3.1/24` (Phase 1 step 9) |
| DHCP | on, pool `.2`–`.254`, lease 1440 min, DNS = router. No fixed reservations. | defaults (pool `.100`–`.249`, fine) |
| Wi-Fi | `HOME` (2.4 GHz) and `HOME-5G` (5 GHz), one shared password | `HOME-X-5G` only (5 GHz, channel 149), new password. The 2.4 GHz radio is dead (hardware), so it is off |
| Port forwards, DMZ, static routes | none | — |
| UPnP | on | install `luci-app-upnp` if a game or P2P app needs it |
| IPv6 | off | turn it off too (Union has IPv6 off) |
| IPTV VLAN | off (the IPTV box is on the modem) | — |
| Mesh | EasyMesh on, no satellites joined | — |
| Remote management / telnet | off | — |
| Admin login | none | none either (Jody, 2026-10-17): LuCI and SSH stay open without a password, as on the H3C today |

## Phase 1: flash (the TX1801's Wi-Fi is down from here until Phase 2 ends)

**Done 2026-10-17** (Klaude drove the serial console from DT-26; Jody did the cables, adapter and sudo). OpenWrt
25.12.5 r33051 installed, `bootflag=0`, LAN `192.168.3.1/24`, WAN DHCP from the modem (`192.168.1.21`), Wi-Fi off
(OpenWrt default). U-Boot's `=>` prompt came from tapping `0` after "U-Boot" appeared; the H3C console's
`reboot` asks `[Y/N]`. The steps below are kept for a redo (E1/E4/E5).

Tip: the router changes its SSH identity at every stage, so `ssh` will refuse with "REMOTE HOST IDENTIFICATION HAS
CHANGED". Before starting, run this once in the terminal you use (it only lasts for that terminal):
```bash
alias ssh='ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'; alias scp='scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no'
```

1. DT-26's Wi-Fi on **`HOME-5G`** (pinned to router B, L1). Check Claude still answers.
2. Cable from DT-26's Ethernet port to the TX1801's **LAN1**. Unplug the TX1801's **WAN** cable (nothing reaches the
   modem while we experiment). Give DT-26's Ethernet the flashing addresses (no gateway, so the internet stays on
   Wi-Fi):
   ```bash
   nmcli con add type ethernet ifname eno1 con-name flash ipv4.method manual ipv4.addresses "192.168.124.99/24" ipv6.method disabled
   nmcli con up flash
   ```
3. Start the TFTP server. DT-26's firewall (ufw) is on and the home folder is private, so (Jody's sudo):
   ```bash
   sudo ufw allow in on eno1 from 192.168.124.0/24
   sudo dnsmasq --port=0 --enable-tftp --tftp-root=/home/jody/Projects/BrainStorm/clash-router/offline/tftp --listen-address=192.168.124.99 --bind-interfaces --user=jody --group=jody --pid-file=/run/tftp-flash.pid
   ```
   Afterwards: `sudo kill $(cat /run/tftp-flash.pid)` and `sudo ufw delete allow in on eno1 from 192.168.124.0/24`.
   (Old form, in its own window:)
   ```bash
   sudo dnsmasq --no-daemon --port=0 --enable-tftp --tftp-root=/home/jody/Projects/BrainStorm/clash-router/offline/tftp --listen-address=192.168.124.99 --bind-interfaces
   ```
4. **Serial.** With the top cover off (`docs/img/board-top.jpg`): header **J4**, 4 empty holes in the middle of the
   board, right of the "TX1801 Plus REV:A" print, labelled under the holes, seen from above, left to right
   **`VCC RX TX GND`**. Lay the board on something non-metal, keep the antenna wires attached, and touch a radiator
   or the PC case before handling it (static).

   **A. The adapter straight into J4 (Jody's idea; the plan).** The adapter's pins, from its end, are
   `GND RXD TXD` then two power pins (confirmed from the seller's product photo; the yellow
   jumper is the 3.3 V/5 V switch). J4 from its GND end is `GND TX RX VCC`, so
   lined up GND to GND, every pin meets its partner: RXD↔TX, TXD↔RX. Only power is in the way:
   - **Set the adapter's switch to 3.3 V.**
   - **Bend the two power pins out of the way** (up, away from the board), so the 4th pin doesn't go into J4's
     VCC hole and neither touches anything on the board.
   - Push GND, RXD and TXD into J4's GND, TX and RX holes, with GND at J4's right end (beside the "J4" print).
     The pins are thinner than the holes: tilt the adapter slightly so they press on the metal rings, and tape it
     there. A USB extension cable keeps the PC from levering on it.

   **B. Backup: wires** (if A won't sit still). Use 3 of the 4 jumper wires that come with the adapter:
   1. Put their female ends on the adapter's GND, RXD and TXD pins; note which colour is on which.
   2. Cut each wire about 2 cm from its other end. Strip 6–8 mm: score the plastic lightly all round with
      scissors, without cutting the copper, and pull it off.
   3. Twist the strands tight into one stiff strand, then fold the tip back on itself once: twice as thick, it
      fits the hole better. Cut off any stray strand: J4's holes are 2.54 mm apart, and a stray could touch the
      next one (RX sits next to VCC).
   4. Push each bare end into its hole and bend it over so it presses on the metal ring: adapter **GND→GND**,
      **TXD→RX**, **RXD→TX**, nothing in VCC. Tape each wire down beside its hole.
   Better still, if there's a scrap network cable: its 8 inner wires are solid copper (stiff, about 0.5 mm), and
   a 5 cm piece stripped at both ends goes into the jumper's female socket at one end and the J4 hole at the
   other. In `screen`: readable text = good; garbage or text stopping = a wire moved, press it back; nothing at
   all = swap the TX and RX wires (harmless).

   (Closed router instead: the same holes through the bottom vent, 7th slot, Phase 0 step 1; mirrored from below:
   GND on the left.) Then:
   ```bash
   screen /dev/ttyUSB0 115200
   ```
   (Quit screen: Ctrl+A, then K, then Y.) Press Enter: you should see a prompt or boot text. Garbage characters mean
   wrong baud; nothing at all means swap TX and RX.
5. Type `reboot`, confirm with `Y`, and **keep tapping `0`** while it boots, to stop in U-Boot. (No prompt to type
   into? Pull the power, plug it back in, tap `0`.)
6. In U-Boot (this loads OpenWrt into RAM only; the flash is untouched, a power cut brings H3C back):
   ```
   tftp 0x80010000 192.168.124.99:initramfs.bin
   bootm 0x80010000
   ```
   When the boot text stops, press Enter for the `root@OpenWrt` prompt (still in screen) and move the router off
   `192.168.1.1`, which is the modem's address on DT-26's Wi-Fi:
   ```
   uci set network.lan.ipaddr='192.168.124.1/24'; uci commit network; service network restart
   ```
7. **Done 2026-10-17:** `backup/` holds `mtd0-u-boot.bin`, `mtd1-u-boot-env.bin`, `mtd2-exp.bin`,
   `mtd3-factory.bin` (Wi-Fi calibration), `mtd4-firmware.bin` (H3C's system, 118 MiB), streamed over SSH;
   sizes match `/proc/mtd` and the SHA-256 sums match ones computed on the router. (Note: `uci` in OpenWrt 25.12
   wants the address with `/24`, or it becomes `/32` and unreachable.)
   **Back up the H3C firmware: our only way back** (H3C doesn't publish it). From DT-26:
   ```bash
   ssh root@192.168.124.1 'cat /proc/mtd'
   ssh root@192.168.124.1 'dd if=/dev/mtd1 of=/tmp/u-boot-env.bin && dd if=/dev/mtd4 of=/tmp/firmware.bin'
   mkdir -p ~/Projects/BrainStorm/clash-router/backup && cd ~/Projects/BrainStorm/clash-router/backup
   scp -O root@192.168.124.1:/tmp/u-boot-env.bin root@192.168.124.1:/tmp/firmware.bin .
   ssh root@192.168.124.1 'cat /proc/mtd' > mtd-table.txt; sha256sum *.bin > SHA256SUMS
   ```
   Also save every other small partition `cat /proc/mtd` lists (`mtd0`, `mtd2`, `mtd3`: bootloader and Wi-Fi
   calibration) the same way: they're tiny and irreplaceable. Copy `backup/` to a USB stick or your phone too.
   **Don't continue until the files are copied off the router** and each file's size matches its partition's size
   in `mtd-table.txt` (the 2nd column, in hex: `printf '%d\n' 0x<size>` turns it into bytes for `ls -l`).
8. Install for real (the router reboots into OpenWrt, about 3 min; watch it in screen):
   ```bash
   scp -O ~/Projects/BrainStorm/clash-router/offline/openwrt-25.12.5-*-sysupgrade.bin root@192.168.124.1:/tmp/sysupgrade.bin
   ssh root@192.168.124.1 'fw_setenv bootargs; fw_setenv bootflag 0; sysupgrade -n /tmp/sysupgrade.bin'
   ```
9. The installed OpenWrt starts at `192.168.1.1` again. When screen shows the boot is done, press Enter and give it
   its final address:
   ```
   uci set network.lan.ipaddr='192.168.3.1/24'; uci commit network; service network restart
   ```
   Then put DT-26's Ethernet back on DHCP (it gets a `192.168.3.x` address from OpenWrt):
   ```bash
   nmcli con down flash; nmcli con up "Wired connection 1"
   ```

## Phase 2: a plain OpenWrt router (no Clash yet)

**Done 2026-10-17.** Wi-Fi `HOME-X-5G` (5 GHz only, channel 149, WPA2/WPA3; Jody set the password in LuCI), flow
offloading (software and hardware) on, IPv6 off on WAN and LAN, time zone Asia/Shanghai. Test: a China mirror
download on DT-26 ran at **112 MB/s** (1.12 GB in 10 s, full gigabit) with the router's CPU 95 % idle. Jody's
phone on `HOME-X-5G` loads websites.

- **The 2.4 GHz radio is dead (hardware), so it's turned off** (`wireless.radio0.disabled=1`). The router heard 0 of the
  8 neighbouring 2.4 GHz networks DT-26 sees, and nothing heard it, before and after a cold reboot. Its calibration
  data matches the factory backup byte for byte, and the H3C firmware's 2.4 GHz was already silent before flashing.
  The model ships with working 2.4 GHz (2×2, 574 Mbps), so this unit's part failed at some point. Nothing needs it:
  phones and laptops use 5 GHz, and 2.4 GHz-only gadgets stay on the ZTEs' `HOME`.
- **5 GHz is pinned to channel 149**: `auto` picked 52, a radar channel (it must go quiet for a minute whenever it
  detects radar, and at every boot). The ZTEs use 36–48.
- LuCI asked "Check online for firmware upgrades": answered **No** (an upgrade would wipe Clash; we upgrade on purpose
  only, with a backup).

To redo it from scratch (e.g. after a reset), from DT-26:

1. Settings over SSH:
   ```bash
   ssh root@192.168.3.1 'uci set wireless.radio0.disabled=1; uci set wireless.radio1.country=CN; uci set wireless.radio1.channel=149; uci set wireless.default_radio1.ssid=HOME-X-5G; uci set wireless.default_radio1.encryption=sae-mixed; uci set firewall.@defaults[0].flow_offloading=1; uci set firewall.@defaults[0].flow_offloading_hw=1; uci set network.wan6.disabled=1; uci -q delete network.lan.ip6assign; uci -q delete network.globals.ula_prefix; uci set dhcp.lan.dhcpv6=disabled; uci set dhcp.lan.ra=disabled; uci set system.@system[0].zonename=Asia/Shanghai; uci set system.@system[0].timezone=CST-8; uci commit; reload_config'
   ```
2. Password: open `http://192.168.3.1` in Chrome, user `root`, password empty, **Log in**. Then **Network →
   Wireless**. In the `SSID: HOME-X-5G` row (not the "MediaTek MT7915E" radio rows) click **Edit**, open the
   **Wireless Security** tab, type the password in **Key**, then **Save**, **Enable** and **Save & Apply**.
3. ✅ A phone sees and joins `HOME-X-5G`.

**No "Clash" (or VPN or proxy, in any language) in any name others can see:** Wi-Fi names, the router's hostname (keep
the default `OpenWrt`). Join `HOME-X-5G` only on devices that should get Clash.

**This is a complete, safe stopping point.** Our router is a normal router; DT-26's Clash Verge still does Clash;
the rest of the house is on the ZTEs as always.

## Phase 3: Clash on the router (Nikki)

**Done 2026-10-18.** Nikki 1.26.2 with mihomo 1.19.32 runs Union for every device on `HOME-X-5G`. Tested: through the
router's Clash, Google, YouTube and GitHub load with a US exit; 🤖 AI sits on provider B's US node as Union intends; China
sites resolve to real China addresses and skip Clash. Jody's phone on `HOME-X-5G` (its own Clash app off): Google,
YouTube, Baidu and ipinfo.io ("US") all work. Clash uses about 90 MB of the router's RAM, with 88 MB still free.
**DT-26 is exempt for now** (by MAC) and keeps its own Clash Verge until Phase 4.

- **The loop bug (fixed):** with "proxy the router's own traffic" on, the router caught Clash's own connections to
  provider B's servers (foreign addresses) and fed them back into Clash ("reject loopback"), so all 29 provider B nodes
  looked dead. provider A escaped only because its relays have China addresses. Fix: `nikki.proxy.router_proxy=0`.
  The router's own traffic (updates, time) goes direct; devices on the Wi-Fi still go through Clash.
- **LuCI → Services → Nikki** shows the same settings. Don't turn "Router proxy" back on.

To redo it from scratch (e.g. after a reset; Phase 2 done first), from DT-26:

1. Install (the router fetches the other packages it needs from OpenWrt's servers):
   ```bash
   scp -O ~/Projects/BrainStorm/clash-router/offline/nikki_mipsel_24kc-openwrt-25.12.tar.gz root@192.168.3.1:/tmp/
   ssh root@192.168.3.1 'cd /tmp && mkdir nikki && tar xzf nikki_*.tar.gz -C nikki && apk update && apk add --allow-untrusted nikki/nikki-*.apk nikki/mihomo-meta-*.apk nikki/luci-app-nikki-*.apk && rm -rf /tmp/nikki*'
   ```
   (The last part frees about 70 MB of RAM: `/tmp` lives in memory.)
2. Seed what the router can't download from China by itself: geodata, the cached node lists and the dashboard
   (the dashboard comes from GitHub, so download it on DT-26 through its Clash first):
   ```bash
   D=~/.local/share/io.github.clash-verge-rev.clash-verge-rev
   scp -O $D/Country.mmdb $D/geosite.dat root@192.168.3.1:/etc/nikki/run/
   scp -O $D/providers/union-*.yaml root@192.168.3.1:/etc/nikki/run/providers/
   ssh root@192.168.3.1 'chmod 600 /etc/nikki/run/providers/union-*.yaml'
   cd /tmp && curl -sLO https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip && unzip -q dist-cdn-fonts.zip && tar cf - -C dist . | ssh root@192.168.3.1 'mkdir -p /etc/nikki/run/ui && tar xf - -C /etc/nikki/run/ui'
   ```
3. Union: `~/Projects/BrainStorm/clash-router/push-union.py --no-restart` (renders the template with the links,
   never printing them, checks it with `mihomo -t` on the router, installs it).
4. Router-only settings (China bypass; DNS gives China domains real addresses so the bypass works; IPv6 off; no
   passwords; DT-26 exempt until Phase 4), then start:
   ```bash
   ssh root@192.168.3.1 'uci set nikki.config.profile=file:union.yaml; uci set nikki.mixin.ipv6=0; uci set nikki.mixin.dns_ipv6=0; uci set nikki.mixin.authentication=0; uci -q delete nikki.mixin.api_secret; uci set nikki.mixin.geodata_loader=memconservative; uci set nikki.mixin.geox_auto_update=0; uci set nikki.mixin.fake_ip_filter=1; uci -q delete nikki.mixin.fake_ip_filters; for f in "+.lan" "+.local" "*.arpa" "time.*.com" "ntp.*.com" "+.pool.ntp.org" "+.msftconnecttest.com" "+.msftncsi.com" "geosite:private" "geosite:cn"; do uci add_list nikki.mixin.fake_ip_filters="$f"; done; uci set nikki.proxy.ipv6_proxy=0; uci set nikki.proxy.ipv6_dns_hijack=0; uci set nikki.proxy.bypass_china_mainland_ip=1; uci set nikki.proxy.router_proxy=0; uci add_list nikki.@lan_access_control[0].mac=<PC-MAC>; uci set nikki.@lan_access_control[0].proxy=0; uci set nikki.@lan_access_control[0].dns=0; s=$(uci add nikki lan_access_control); uci set nikki.$s.enabled=1; uci set nikki.$s.proxy=1; uci set nikki.$s.dns=1; uci set nikki.config.enabled=1; uci commit nikki; service nikki restart'
   ```
5. ✅ A phone on `HOME-X-5G` with its own Clash app off: google.com loads and ipinfo.io says "US".

## Phase 4: DT-26 onto the router's Clash

**Undone for DT-26 the same night (Jody, 2026-10-18): DT-26 is back on Clash Verge (TUN on) and exempt on the router
again.** The router's processor is too slow to encrypt for the nodes: foreign downloads through it reach about
12 Mbps on one connection (speedtest.net about 30 Mbps), against about 103 Mbps on one connection through Verge on DT-26.
China traffic is full speed either way. The router's Clash stays for phones and other devices on `HOME-X-5G`. To
move DT-26 back onto the router some day, follow the redo steps below; the way-back steps are what was done.

**Done 2026-10-18.** DT-26 uses the router's Clash like every other device (Jody's decision). Clash Verge stays
installed as the backup, with **TUN and system proxy both off**. os-admin's side is "router mode" (OS-Admin commit
`f9d8b37`, check ROUTERCLASH): while Verge's TUN and system proxy are off, the `claude` tweak removes Claude Code's
proxy setting, and turning TUN back on restores it. Tested through the router alone, with Verge quit: Claude API 0.5 s,
claude.ai 1.2 s, Google 1.6 s, Baidu 0.14 s, China mirror download **112 MB/s** with the router's CPU 95 % idle.

- **Lesson from the first try:** a running Claude keeps the proxy setting it started with (`127.0.0.1:7897`, Verge's
  port). Quitting Verge before restarting Claude cut that session off. Always restart Claude right after
  `os-admin check`, and keep Verge open until then.
- **Windows on this PC (DT-W-26)** uses the same network port and MAC, so the exemption covers it too. Had DT-26
  stayed on the router, Windows' Verge (system-proxy mode) would have needed switching off as well.
- While Verge is quit, os-admin warns `CLASH nothing listening on 7897`. That's expected; at the next login Verge
  starts again, idle, with TUN off.

How it was done, and how to redo it (e.g. after a reset):

1. Klaude removes DT-26's exemption on the router (its entry is the first `lan_access_control`):
   `ssh root@192.168.3.1 'uci delete nikki.@lan_access_control[0]; uci commit nikki; service nikki restart'`
2. Jody: Clash Verge (the cat in the tray) → **Settings** → **TUN Mode** off. Leave Verge open.
3. Konsole: DNS from the router only, never the standby Wi-Fi:
   `nmcli con mod "Wired connection 1" ipv4.dns-priority -10 && nmcli dev reapply eno1`
4. Konsole: `os-admin check` → ✅ `claude` applied, three `OK ROUTERCLASH`, `0 FAIL`.
5. Quit Claude (tray → **Quit**) and open it again. Only then quit Verge, if you want it closed.
6. Test: Google, Claude, and a 10-second China download (expect about 112 MB/s).

**The way back (any time the router's Clash fails):** open **Clash Verge** from the app menu → **Settings** → **TUN
Mode** on. DT-26 is online through Verge right away, and Claude works without its proxy setting because TUN catches
everything. Then `os-admin check` (it puts Claude's proxy back), and Klaude puts the exemption back on the router
(Phase 3 step 4, the `lan_access_control` part).

## Living with it (after Phase 3)

- **Same engine as Clash Verge:** Nikki runs mihomo, Union is the same file. A failing node is handled as today:
  the sticky single-country fallback groups move to the next node of that country by themselves. Subscriptions
  refresh themselves on the router.
- **Pick nodes, see latency and logs:** the dashboard at `http://192.168.3.1:9090/ui` from any device on
  `HOME-X-5G` or the cable (works like Clash Verge's Proxies page). If it asks for a backend: host `192.168.3.1`,
  port `9090`, no secret.
- **A device with its own Clash app** (the laptop) turns it off on `HOME-X-5G`, or joins `HOME` instead: two Clashes
  in a row double the hops.
- **China addresses skip Clash entirely** (that's what keeps them fast), so Union's ad block and Huya P2P block
  don't apply to them on the router.
- **Profile settings, update subscriptions, restart:** the router's admin page `http://192.168.3.1` → Services →
  Nikki.
- **Changing Union:** same as now. Klaude edits `OS-Admin/clash/Union.template.yaml` and validates it, then
  `~/Projects/BrainStorm/clash-router/push-union.py` (not os-admin) checks it on the router, installs it and
  restarts Nikki, which takes about 30 seconds. Don't edit Union by
  hand on the router: the template stays the one source.
- **Clash acting up:** stop Nikki (E3). Our router keeps working as a plain router (China sites fine), and DT-26
  turns Clash Verge's TUN back on. Keep the Clash apps on every device as the backup.
- **Going back to H3C's firmware for good:** E5, from `backup/`. Check the backup is complete (Phase 1 step 7)
  before going on, since it's the only copy. The method comes from the developer who added this router to OpenWrt;
  we haven't tested it ourselves.

## Stall watcher (2026-10-18)

A small service on the router (`router/stall-watcher.uc`, ucode, run by procd as `stall-watcher`) that catches a
node that **stalls**: it delivers the first ~16 KB of every response and then hangs, while mihomo's health checks (HEAD
requests only) still call it alive. That happened to a provider's US nodes on 2026-10-18 (X, TikTok, Wikipedia never
loaded). It's a port of os-admin's PC watcher (NODESTALL).

- **How it decides:** every 15 s it reads Clash's live connections from the local controller (no test traffic). A
  node is suspect when TCP connections to 3+ different sites have sat 20–120 s old under 20 KB, unchanged since the
  last look, and none of its connections got past 20 KB in the last minute. Older idle connections are push
  channels and don't count.
- **What it does:** one probe page through the router's own port 7890 confirms it (Wikipedia for 🔰 Proxy,
  anthropic.com for 🤖 AI, Google, GitHub; the whole page within 12 s). If the page comes through, the node is left
  alone for 30 min. If not, the node's **fallback group** is fixed on its next member that delivers (same group, so
  same country; at most 4 tried; never url-test). Every 30 min a fix is lifted, and stays lifted once the group's
  own pick delivers again. A node picked by hand in a select group is only logged.
- **Cost:** about 0.03 s of CPU per 90 s and 1 MB of RAM.
- **See what it did:** `ssh root@192.168.3.1 'logread -e stall-watcher'`. Its current fixes are in
  `/etc/nikki/stall-watcher.json`.
- **Install or update:** `./deploy-watcher.sh` runs the 7 test scenarios on the router (push channels, only two
  stuck sites, a false alarm, a node still downloading, a real stall then lift, a whole country stalling, the own
  pick still stalling) and installs only when all pass. One look with the real controller and a probe per group:
  `ssh root@192.168.3.1 'ucode /usr/share/stall-watcher/stall-watcher.uc check'`.
- **Stop it:** `ssh root@192.168.3.1 '/etc/init.d/stall-watcher stop; /etc/init.d/stall-watcher disable'`. Nikki is
  unaffected.

## Emergencies: what to do when it breaks

**First, always: get online through a lifeline** (L1 router B's Wi-Fi, L2 phone hotspot, L3 modem port), with
DT-26's Clash Verge on. Then Klaude can help again.

| | What you see | What to do |
|---|---|---|
| E1 | Router seems dead after flashing (no Wi-Fi, no web page) | It isn't: U-Boot is never touched. Redo Phase 1 steps 2–6 (serial + TFTP), then step 8. |
| E2 | OpenWrt runs but no internet | WAN cable plugged in? LAN moved off `192.168.1.1` (Phase 1 step 9)? `ssh root@192.168.3.1 'ifup wan; sleep 10; ping -c2 223.5.5.5'` |
| E3 | Internet broke after Clash (Phase 3) | Stop Clash, the router stays a plain router: `ssh root@192.168.3.1 'service nikki stop; service nikki disable'` (or LuCI → Services → Nikki → off) |
| E4 | Locked out (broke the firewall or LAN settings) | **Failsafe, over the serial cable** (its network address would be `192.168.1.1`, the modem's): connect serial (Phase 1 step 4), power the router on, and when screen says "Press the [f] key", press `f` then Enter (or press the reset button several times while the LED blinks fast). At the shell: `firstboot -y && reboot`. OpenWrt is reset to blank: do Phase 1 step 9, then Phase 2. |
| E5 | You want H3C's firmware back | Boot OpenWrt (normal, or the initramfs via Phase 1), copy the backups to `/tmp`, then `mtd write /tmp/mtd1-u-boot-env.bin u-boot-env && mtd write /tmp/mtd4-firmware.bin firmware && reboot` |
| E6 | Nothing works and the house needs internet now | Unplug the TX1801 Plus. Devices use `HOME`/`HOME-5G` (the ZTEs). Fix it another day. |

## Never

- Write anything to the bootloader partition (`mtd0`). That's the one mistake that needs a soldering iron.
- Connect the adapter's VCC pin.
- Start Phase 1 without the L1 rehearsal from Phase 0, or Phase 2 without `backup/` copied off the router.
- Uninstall Clash Verge from DT-26 or the laptop: it's the lifeline, and the laptop needs it away from home anyway.
