# Evidence trail — MT79xx BLE "zombie controller" state

> Machine: AMD laptop, MT7922 combo (BT on USB `13d3:3585`, fw build `20260724143815`), Fedora 44, kernel 7.1.10-200, BlueZ 5.87 (also verified on 5.79 — not a BlueZ regression).
> Addresses below are consistently anonymized: `AA:…:01` adapter · `AA:…:02` keyboard · `AA:…:03` mouse · `AA:…:04` speaker.

## 1. Baseline: the failure is invisible in standard health checks

```
$ bluetoothctl show          # during the failure
Controller AA:AA:AA:AA:AA:01 (public)
  Powered: yes
  Discovering: yes           # adapter "alive"
$ hciconfig hci0 | head -1   # UP RUNNING
```

`connect AA:AA:AA:AA:AA:02` → hangs → timeout. The keyboard, meanwhile, is alive and transmitting (see §3).

## 2. The peripheral side is healthy

- Every disconnect is a clean `HCI Event: Disconnect Complete — Reason: Remote User Terminated Connection (0x13)` — standard BLE power-save nap, identical for mouse and keyboard.
- When the keyboard is finally captured during a pairing-mode broadcast, RSSI is **−58 dBm** — healthy radio, one meter from the host.
- The mouse on the same adapter (simpler re-connect path) usually keeps auto-reconnecting; the keyboard (RPA/directed path) stops being accepted first.

## 3. btmon during the failure: host armed, controller deaf

```
> HCI Event: Disconnect Complete (0x05) plen 4        # keyboard went to sleep
        Handle: 513
        Reason: Remote User Terminated Connection (0x13)
@ MGMT Event: Device Disconnected
        LE Address: AA:AA:AA:AA:AA:02 (Static)
# ~10 s later, host arms recovery: resolving-list entry + privacy mode + scan
< HCI Command: LE Add Device To Resolving List        # IRK for the keyboard
        Address: AA:AA:AA:AA:AA:02 (Static)
< HCI Command: LE Set Privacy Mode / LE Set Extended Scan Enable
        Interval: 60.000 msec  Window: 30.000 msec
# ...and then: zero LE Advertising Report callbacks for that device. Ever.
```

Same capture, keyboard placed in pairing mode (static-address broadcast, no RPA):

```
> HCI Event: LE Extended Advertising Report
        Props: Connectable Scannable
        Address: AA:AA:AA:AA:AA:02 (Static)
        Data: LE Limited Discoverable Mode; HID (0x1812); Appearance: Keyboard; Name "…"
        RSSI: -58 dBm
```

→ The radio path works; the **RPA resolving / directed-acceptance path is what died**.

## 4. The reset that works (instantly, same MAC, no re-pairing)

```
$ sudo modprobe -r btusb btmtk && sudo modprobe btusb
[   12.3] usb 1-5: new high-speed USB device            # re-enumeration
[   12.5] Bluetooth: hci0: HW/SW Version …, Build Time: 20260724143815
[   12.7] Bluetooth: hci0: Device setup in 0.19 s
# keystroke on the keyboard → reconnected within ~2 s, same MAC
```

`systemctl restart bluetooth` alone was **not** reliable; driver rebind is. (Same reset recommended by the Framework knowledge base for MT79xx.)

## 5. The smoking gun: live connection dropped by the host mid-use

During active typing (not idle, no 0x13 involved), the kernel logged:

```
kernel: Bluetooth: hci0: ACL packet for unknown connection handle 3837
kernel: Bluetooth: hci0: ACL packet for unknown connection handle 3837
```

The keyboard was transmitting keystroke data on a connection the host had **unilaterally forgotten**. User-visible effect: a stuck key (the key-up report never arrived), then disconnection. This is the strongest single line of evidence that the corruption is host/controller-side connection-table damage — the peripheral did nothing wrong. It also precedes/alternates with the zombie state of §3 on the same machine.

## 6. Corruption is progressive, with precursors

Kernel/bluez markers observed **before** failures:

- `bluetoothd: Wrong size of start discovery return parameters` + `org.bluez.Error.NotReady` — adapter "half-dead" event, captured **spontaneously with no audio device attached** (so SCO is not the sole trigger);
- `Bluetooth: hci0: SCO packet for unknown connection handle ×3` — after an HFP earbuds session teardown; failures became frequent afterwards;
- Background disconnect rate is constant (~8/25 h, ~10/39 h, ~6/10 h across boots) — what changes is **whether they recover**, not how often they happen.

## 7. What was ruled out (and how)

| Hypothesis | Ruled out by |
|---|---|
| Keyboard firmware "dies" | Clean 0x13 every time; strong RSSI; recovers instantly after rebind, same MAC |
| BlueZ regression | Downgrade 5.87→5.79, failure persisted (5.79 matches an Arch thread for a different symptom class) |
| USB autosuspend | Disabled via udev (`power/control=on`) — fixes slow reconnect, not the zombie state |
| A2DP audio coexistence | Speaker is a constant, not a variable; keyboard ran fine for 3 h with A2DP streaming; spontaneous case with no audio |
| System update that day | `dnf history` audit: only mesa/firefox/curl that morning; kernel and firmware were 3–6 days old |

## 8. Trap: tri-mode peripherals increment MAC on re-pair

Observed chain on two peripherals (keyboard `…02`, mouse `…03`-style): every remove+re-pair bumps the static address by one (`…6B→6C→6D→6E`). Removing the bond when this bug hits creates a deadlock: peripheral directed-pages the old host, host no longer knows it — looks exactly like "dead keyboard" and destroys evidence. **Rebind first; never remove.**
