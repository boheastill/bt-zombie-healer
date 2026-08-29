# Upstream bug report (ready to send) — linux-bluetooth

Send as plain text to linux-bluetooth@vger.kernel.org
Cc: sean.wang@mediatek.com, chris.lu@mediatek.com, luiz.dentz@gmail.com
Attach or link: btmon snoop covering the full cycle (normal -> SCO teardown -> 0x13 -> zombie -> rebind recovery).

Subject: Bluetooth: btusb/btmtk: MT79xx silent BLE resolving-path corruption after long LE reconnect cycling + SCO teardown (13d3:3585)

Hello Bluetooth maintainers,

We observed a reproducible controller state corruption on a MediaTek MT79xx
Bluetooth part (USB 13d3:3585, btusb+btmtk, firmware build 20260724143815).

[Environment]
- MT7922 combo card, BT on USB (13d3:3585)
- Fedora 44, kernel 7.1.10-200, BlueZ 5.87 (also verified on 5.79 - not a BlueZ regression)
- Peripherals: BLE HID keyboard and mouse (HoG), one BR/EDR A2DP speaker, HFP earbuds (occasional)

[Symptoms]
1. BLE HID peripherals disconnect on idle with clean 0x13 (Remote User Terminated)
   and normally reconnect within 1-2 s via RPA/directed advertising.
2. After long-running LE disconnect/reconnect cycling (dozens per day) and
   especially after an abnormal SCO teardown
   (dmesg: "SCO packet for unknown connection handle" x3, HFP session ended),
   the controller enters a silent half-dead state:
   - HCI command channel remains responsive (Powered: yes, scanning can be
     enabled, hciconfig UP RUNNING);
   - the affected peripheral keeps transmitting directed advertisements
     (verified by rf capture during pairing mode: -58 dBm at 1 m), but the
     controller never reports LE Advertising Reports for it and LE connections
     to it never complete (connect -> timeout);
   - resolving list entries are configured correctly by the host
     (btmon: LE Add Device To Resolving List + Set Privacy Mode + extended scan).
2b. In a second failure mode, an actively-used connection is dropped by the
   host/controller mid-use. Kernel log during typing:
   "Bluetooth: hci0: ACL packet for unknown connection handle 3837" (x2)
   — the peripheral keeps transmitting keystroke ACL data on a connection
   the host side has unilaterally forgotten. User-visible: stuck key
   (missing key-up report), then disconnection.
3. A spontaneous "half-dead" event was also captured with no audio device
   attached (bluetoothd: "Wrong size of start discovery return parameters",
   mgmt NotReady), so SCO is an accelerator, not the only trigger.
4. Recovery: modprobe -r btusb btmtk && modprobe btusb restores operation
   instantly (same peripheral MAC, no re-pairing). systemctl restart bluetooth
   is not reliable for this state.

[Questions]
- Is this a known firmware scheduler/resolving-list limitation for MT79xx?
- Would an in-driver heartbeat or subsystem-reset on "scan armed but zero
  advertisement callbacks for a bonded device" be an acceptable mitigation?

[Logs]
- btmon snoop: [link] (full cycle as described above)
- dmesg excerpt: [link]
- lsusb -v descriptors: [link]

Thanks,
<your name>
