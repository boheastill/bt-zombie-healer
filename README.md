# bt-zombie-healer

Auto-healing for the **MediaTek MT79xx Bluetooth "zombie controller" state** — BLE devices keep advertising, the host silently stops accepting them. Watchdog detects, driver-rebind fixes, you just type a key.

## The bug (30-second read, evidence in `docs/`)

On MT7921/MT7922/MT7925 combo cards (BT part on USB, `btusb`+`btmtk`), the controller can enter a **silent half-dead state**:

- The HCI command channel stays alive — `bluetoothctl show` looks healthy, `hciconfig` says UP RUNNING.
- But the **RPA resolving / directed-advertising acceptance path is dead**: a BLE keyboard/mouse disconnects for its normal power nap (`0x13 Remote User Terminated`), keeps transmitting directed advertisements — and the host **never reports or accepts them**. `connect` times out forever.
- `btmon` proof: at the moment of failure the host has scanning + IRK resolving list configured and running, yet zero advertisement callbacks for the peripheral; the peripheral's signal is strong (−58 dBm). Re-running the capture while the *same* keyboard pairs in pairing mode shows it instantly — static address, no resolving needed. (Full trail: `docs/evidence.md`)
- **Reset that works**: `modprobe -r btusb btmtk && modprobe btusb` — instant recovery, same MAC, no re-pairing. (Same reset as the official Framework knowledge base.)

Triggers observed on the affected machine: long-running LE disconnect/reconnect cycling (state degrades over days) plus an abnormal SCO teardown (`SCO packet for unknown connection handle` in dmesg). A spontaneous case with no audio device attached was also captured — SCO is an accelerator, not the only cause.

This is a **workaround, not a fix** — the corruption lives in closed firmware. Upstream has no direct fix in mainline as of kernel 7.1; the practical goal is to make the failure invisible (detect ≤35 s, reset in ~3 s).

## What you get

| File | Purpose |
|---|---|
| `bt-watch.sh` | Watchdog (user systemd service): polls connected devices every 10 s; on "down for >25 s" auto-runs the rebind helper and sends a desktop notification ("just type a key"). Logs state changes + kernel evidence at `~/.local/state/bt-watch.log` |
| `bt-rebind.sh` | The reset itself (root, whitelisted via sudoers — no password prompt) |
| `70-bt-rebind-sleep.sh` | Resume hook via `/usr/lib/systemd/system-sleep/` (note: a `suspend.target.wants` unit does **not** fire on resume — use system-sleep scripts) |
| `install.sh` | One-shot installer: sudoers whitelist, udev autosuspend-off rule, system-sleep hook, user service |
| `docs/evidence.md` | The forensic trail: timeline, btmon excerpts, what was ruled out and why |
| `docs/bug-report.md` | Ready-to-send upstream report body (linux-bluetooth) |

Optional hardening (documented in evidence.md): disable HFP/HSP in WirePlumber to eliminate the SCO trigger (cost: BT headsets lose mic).

## Quick start

```bash
git clone https://github.com/boheastill/bt-zombie-healer && cd bt-zombie-healer
./install.sh          # sudo asked for privileged parts
# optional: match your own devices
systemctl --user edit bt-watch   # or edit ~/.local/bin/bt-watch.sh  BT_WATCH_DEVICES
```

If your BLE devices already went missing right now: `sudo /usr/local/bin/bt-rebind.sh`, then press any key on the device.

## Side effects & manual-recovery coexistence

The watchdog is deliberately **not aggressive**:

- **You stay in control**: if you start a manual recovery (pairing-mode broadcast detected as an unpaired device entry), the watchdog **yields for 3 minutes** and lets you finish (GNOME panel re-pairing is a valid path — a re-pair even clears the zombie state; it just costs you a MAC bump on tri-mode peripherals).
- **Every auto-rebind declares its side effects** first (logged + shown in the notification): all connected BT devices blink off for 2-5 s; a playing BT audio stream interrupts briefly; the GNOME BT panel may show stale state until reopened.
- Reset path is the proven `modprobe` rebind (Framework-KB equivalent). The theoretically nicer USB `authorized 0/1` toggle **bricked the bluez device table once on the test machine** — documented, avoided.

## Scope & honesty

- Verified on: MT7922 (USB 13d3:3585), Fedora 44, kernel 7.1.10, BlueZ 5.79/5.87.
- The watchdog heals the *silent zombie state*. It does not fix: adapter fully disappearing from USB (see [moolooite/mt7925e-bt-heal](https://github.com/moolooite/mt7925e-bt-heal/) for that class), nor the firmware bug itself.
- Avoid the destructive "fix": **don't remove/re-pair** tri-mode peripherals when this hits — many of them increment their MAC on every re-pair, which destroys the bond and hides the real cause.

## License

MIT
