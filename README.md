# bt-zombie-healer

**A silent MediaTek MT79xx Bluetooth failure mode, characterized and made invisible.**

*The characterization is the project; the healer is a convenience.*

Your BLE keyboard/mouse works fine, then one day: it disconnects mid-use (maybe with a stuck key), and never comes back — re-pairing "fixes" it, rebooting "fixes" it, and the Bluetooth panel keeps saying everything is healthy. It is not your peripherals, and it is (probably) not BlueZ.

> **For the impatient**: `sudo modprobe -r btusb btmtk && modprobe btusb`, then press a key on the device. If that instantly fixes it — every time — you likely have the failure mode described here ([§2](#2-the-model-zombie-controller-state)). Short of time? **The one thing to remember is the first row of the table in §3.**
>
> **One-line install of the watchdog** (guarded: aborts on non-MediaTek BT):
> ```bash
> curl -fsSL https://raw.githubusercontent.com/boheastill/bt-zombie-healer/main/install.sh | bash
> ```

---

## 1. One organ, several diseases — and one of them is ours

Scattered across distro trackers, these look like unrelated bugs. Each got its own folk remedy. **The remedy that works is the differential diagnostic:**

| What people report | The remedy that "works" | Verdict | Where |
|---|---|---|---|
| "BT adapter disappears after suspend/update" | full power-off, or reload `btusb` | adapter-gone disease | [bazzite #3112](https://github.com/ublue-os/bazzite/issues/3112), [bluefin #4728](https://github.com/ublue-os/bluefin/issues/4728) |
| "MT7925 fails to initialize — WMT command timeout" | upstream `btmtk` fix (landed in 7.1-rc) | init-fails disease | [pop-os #4001](https://github.com/pop-os/pop/issues/4001) |
| "BT dies after firmware update" | `usbcore.autosuspend=-1` | autosuspend mishandling | [RH Bugzilla #2372880](https://bugzilla.redhat.com/show_bug.cgi?id=2372880) |
| "BLE devices won't reconnect until reboot" | `modprobe -r btusb` | **zombie state (this repo)** | [AskUbuntu 1387234](https://askubuntu.com/questions/1387234/bluetooth-only-works-after-reloading-module-btusb), [Level1Techs](https://forum.level1techs.com/t/bluetooth-issues-with-mediatek-mt7925-controller-on-linux/244440) |
| "corrupted ACL packets, segfaults" | driver reload | possibly zombie-adjacent | [Level1Techs](https://forum.level1techs.com/t/bluetooth-issues-with-mediatek-mt7925-controller-on-linux/244440) |

We hit the last row on an MT7922 and dug past the remedy. This repo is the result: **a characterization of the zombie state, the evidence behind it ([docs/evidence.md](docs/evidence.md) — the core asset), and an auto-recovery watchdog.** The knowledge is the contribution; the script is convenience.

## 2. The model: "zombie controller state"

In plain terms: the BT chip is not dead, it is **half-deaf** — it answers every question you ask it directly, but it never hears your peripherals knocking anymore.

Three claims, in decreasing order of certainty:

1. **(Directly observed)** The HCI command plane stays alive while the BLE acceptance path is dead. `bluetoothctl show` looks healthy, scanning can be enabled — yet for the affected peripherals there are **zero advertisement callbacks** and every `connect` times out. The smoking gun, twice captured mid-use:
   ```
   kernel: Bluetooth: hci0: ACL packet for unknown connection handle 3837
   ```
   Peripheral keystroke data arriving for a handle missing from the host-side connection table — a live connection dropped from the bookkeeping mid-use. (User-visible: a stuck key — the key-up report died with the connection — then silence.) Whether it is the host stack or the controller that lost the handle is not yet separable; the same handle recurring twice favors the corruption being persistent on one side.
2. **(Directly observed)** The failure is *stateful and progressive*: it develops after days of normal LE sleep/reconnect cycling (disconnect rate roughly stable across three boots: 8/25 h, 10/39 h, 6/10 h), with kernel precursors (`Wrong size of start discovery return parameters`, SCO handle leaks after HFP teardown), and a driver rebind clears it instantly — same MACs, no re-pairing.
3. **(Strong inference, falsifiable)** During the failure the peripheral keeps advertising while the controller has stopped resolving/accepting it. Supported by: in the same captures, pairing-mode (static-address, undirected) broadcasts *are* received at −58 dBm while RPA-directed reconnects never are — i.e. **the advertising plane was alive, the resolving/acceptance plane was dead**. Not yet confirmed by a second receiver: if you hit this failure, a 1-minute phone-side BLE scan (nRF Connect) turns this into direct evidence either way — see [§5](#5-open-questions--how-to-help) and the [issue template](.github/ISSUE_TEMPLATE/bug_report.md).

## 3. What fixes it — and what doesn't

| Action | Effect |
|---|---|
| `modprobe -r btusb btmtk && modprobe btusb` | **Reliable instant recovery** (matches the [official Framework KB procedure](https://knowledgebase.frame.work/ubuntu-bluetooth-S1PGxfho) for MT79xx) |
| `systemctl restart bluetooth` | Sometimes; not reliable for this state |
| USB `authorized 0/1` toggle | Theoretically nicer; **corrupted the bluez device table once on our machine** — avoid |
| Remove + re-pair the peripheral | Works, but destructive: on two tri-mode peripherals observed, **every re-pair incremented the MAC** (`…6B→6C→6D→6E`), destroying the bond and the evidence. Rebind first; never remove. |
| Disable USB autosuspend (udev) | Fixes the *slow reconnect* flavor; good hygiene, not a cure |
| Disable HFP/HSP (WirePlumber) | Removes the biggest SCO trigger; costs BT-headset mic |

## 4. The watchdog (convenience, not the contribution)

User-level systemd service. **Detection**: polls `bluetoothctl devices Connected` every 10 s (DBus PropertiesChanged would be event-grade — patches welcome); **recovery**: keyboard down >25 s → sudoers-whitelisted rebind → worst-case ~35 s to green. Design rules:

- **Manual recovery always wins** — a pairing-mode broadcast from your device means *you* are fixing it; the watchdog yields for 3 minutes.
- **Every rebind declares its side effects** first (which devices will blink, whether audio was playing).
- **Forensics mode**: `BT_WATCH_FORENSICS=1` in `~/.local/bin/bt-watch.sh` → alert-and-log only, never auto-rebind — for users who want to capture evidence for the open questions instead of masking them.
- Logs state transitions + kernel evidence to `~/.local/state/bt-watch.log` — your forensic trail for free.

```bash
./install.sh      # guarded: aborts unless a MediaTek BT adapter (13d3/0e8d/0489) is detected
./uninstall.sh    # full reverse: sudoers entry, udev rule, sleep hook, services
```

The exact privileged surface is one sudoers line, shown in [install.sh](install.sh) for audit: `ALL=(root) NOPASSWD: /usr/local/bin/bt-rebind.sh`.

## 5. Open questions & how to help

We have **not** run these yet — each is cheap, and each would sharpen the model:

1. **Second-receiver capture** during a failure (phone nRF Connect, or a second USB BT dongle running btmon as sniffer — stricter): does the peripheral keep advertising? Settles claim 3.
2. **`btmgmt conn-info` / controller-side connection table** during a failure: whose bookkeeping lost the handle — host or controller?
3. **Firmware bisect** (20260724 ↔ 20260224): in progress on the affected machine, verdict pending.

If you hit this failure: please capture `journalctl -k --since "-1h"` around the incident, note whether a rebind recovered it, and open an issue with the [template](.github/ISSUE_TEMPLATE/bug_report.md). Reports either way — confirmed or refuted — improve the map.

## 6. Root cause status — honest

Prime suspect: MediaTek firmware (closed microcode); next: btusb URB lifecycle. Same hardware reportedly behaves fine on Windows (anecdotal, our machine included) — consistent with a Linux-stack issue, not HW. To our knowledge, as of kernel 7.1 (checked: linux-bluetooth list, mainline btusb/btmtk commits) there is no direct fix for this silent path — mainline has reset-mechanism hardening only. Discriminators we would accept as verdicts: if a failure shows firmware-side state visible to btmon after rebind, that indicts firmware; if URB errors consistently precede symptoms, that indicts btusb. We will re-judge on evidence, not vibes.

## 7. Scope

Verified as of **2026-08-29** on: MT7922 (USB 13d3:3585), Fedora 44, kernel 7.1.10, BlueZ 5.79 & 5.87. Related reports suggest the family covers MT7921/7925 — unverified here. This is a **mitigation, not a cure**; the goal is that you stop noticing the disease. MIT license. [中文版 README](README.zh-CN.md)
