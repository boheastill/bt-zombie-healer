# bt-zombie-healer

**A silent MediaTek MT79xx Bluetooth failure mode, characterized and made invisible.**

Your BLE keyboard/mouse works fine, then one day: it disconnects mid-use (maybe with a stuck key), and never comes back — re-pairing "fixes" it, rebooting "fixes" it, and the Bluetooth panel keeps saying everything is healthy. You are not alone, it is not your peripherals, and it is (probably) not BlueZ. We traced this class of failures to one mechanism and packaged the recovery.

> **For the impatient**: `sudo modprobe -r btusb btmtk && modprobe btusb`, then press a key on the device. If that instantly fixes it — every time — you likely have the failure mode described here. The watchdog in this repo does exactly this, automatically.

---

## 1. One failure mode, many disguises

Scattered across distro trackers, these look like unrelated bugs. Each got its own folk remedy:

| What people report | The folk remedy that "works" | Where |
|---|---|---|
| "BT adapter disappears after suspend/update" | full power-off, or reload `btusb` | [bazzite #3112](https://github.com/ublue-os/bazzite/issues/3112), [bluefin #4728](https://github.com/ublue-os/bluefin/issues/4728) |
| "MT7925 fails to initialize — WMT command timeout" | wait for the upstream `btmtk` fix (landed in 7.1-rc) | [pop-os #4001](https://github.com/pop-os/pop/issues/4001) |
| "BT dies after firmware update" | kernel cmdline `usbcore.autosuspend=-1` | [RH Bugzilla #2372880](https://bugzilla.redhat.com/show_bug.cgi?id=2372880) |
| "BLE devices won't reconnect until reboot" | `modprobe -r btusb` | [AskUbuntu 1387234](https://askubuntu.com/questions/1387234/bluetooth-only-works-after-reloading-module-btusb) |
| "corrupted ACL packets, segfaults" | driver reload | [Level1Techs](https://forum.level1techs.com/t/bluetooth-issues-with-mediatek-mt7925-controller-on-linux/244440) |

We hit one of these on an MT7922 and dug past the remedies. This repo is the result: **a characterization of the mechanism, the evidence, and an auto-recovery watchdog.** The knowledge is the contribution; the script is convenience.

## 2. The model: "zombie controller state"

> 人话版:蓝牙芯片没有死透,它只是"半聋"——你问它话它都答,但设备来敲门它永远装听不见。

Three claims, in decreasing order of certainty:

1. **(Directly observed)** The HCI command plane stays alive while the BLE acceptance path is dead. `bluetoothctl show` looks healthy, scanning can be enabled — yet for the affected peripherals there are **zero advertisement callbacks** and every `connect` times out. The smoking gun, twice captured mid-use:
   ```
   kernel: Bluetooth: hci0: ACL packet for unknown connection handle 3837
   ```
   The peripheral is transmitting live keystroke data on a connection the host has *unilaterally forgotten*. (User-visible: a stuck key — the key-up report died with the connection — then silence.)
2. **(Directly observed)** The failure is *stateful and progressive*: it develops after days of normal LE sleep/reconnect cycling, with kernel precursors (`Wrong size of start discovery return parameters`, SCO handle leaks after HFP teardown), and a driver rebind clears it instantly — same MACs, no re-pairing.
3. **(Strong inference, falsifiable)** During the failure the peripheral keeps advertising; the controller has stopped resolving/accepting. Supported by: pairing-mode captures show the same keyboard's radio healthy at −58 dBm, and the host-side resolving list is correctly armed. *Not yet confirmed by a second receiver — if you hit this failure, a 1-minute phone-side BLE scan (nRF Connect) would turn this into direct evidence either way.*

**Differential diagnosis** (why the folk remedies diverge): adapter-gone → power-cycle fixes; init-fails (WMT timeout) → fixed in 7.1-rc; **zombie state (this repo)** → rebind fixes. Different diseases, same organ.

## 3. What fixes it — and what doesn't

| Action | Effect |
|---|---|
| `modprobe -r btusb btmtk && modprobe btusb` | **Reliable instant recovery** (also the official Framework KB procedure for MT79xx) |
| `systemctl restart bluetooth` | Sometimes; not reliable for this state |
| USB `authorized 0/1` toggle | Theoretically nicer; **bricked the bluez device table once on our machine** — avoid |
| Remove + re-pair the peripheral | Works, but destructive: tri-mode peripherals often **increment their MAC on every re-pair** (`…6B→6C→6D→6E` observed), destroying the bond and the evidence. Don't. |
| Disable USB autosuspend (udev) | Fixes the *slow reconnect* flavor; good hygiene, not a cure |
| Disable HFP/HSP (WirePlumber) | Removes the biggest SCO trigger; costs BT-headset mic |

## 4. The watchdog (convenience, not the contribution)

User-level systemd service, 10 s polling: on keyboard down >25 s it runs a sudoers-whitelisted rebind and notifies you to just type a key. Design rules:

- **Manual recovery always wins** — a pairing-mode broadcast from your device means *you* are fixing it; the watchdog yields for 3 minutes.
- **Every rebind declares its side effects** first (which devices will blink, whether audio was playing).
- Logs state transitions + kernel evidence to `~/.local/state/bt-watch.log` — your forensic trail for free.

```bash
./install.sh     # sudoers whitelist, udev autosuspend-off, system-sleep hook, user service
```

## 5. Root cause status — honest

Firmware-level (closed-source MediaTek microcode) is the prime suspect (65%), btusb URB handling next (20%). No direct fix exists upstream as of kernel 7.1; mainline has reset-mechanism hardening but nothing for this silent path. A firmware bisect (20260724 → 20260224) is in progress on the affected machine; a ready-to-send upstream report is included (`docs/bug-report.md`).

## 6. Scope

Verified on: MT7922 (USB 13d3:3585), Fedora 44, kernel 7.1.10, BlueZ 5.79 & 5.87. Related reports suggest the family covers MT7921/7925. This is a **mitigation, not a cure** — the goal is that you stop noticing the disease. MIT license.
