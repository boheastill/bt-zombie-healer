---
name: zombie-state report
about: Report a suspected MT79xx BLE zombie-state failure
---
**Kernel / distro / BlueZ versions:**
**BT adapter (lsusb line):**

**Symptom** (check all that apply):
- [ ] BLE peripheral never reconnects after idle/mid-use disconnect
- [ ] Stuck key right before the disconnect
- [ ] `connect` times out while `bluetoothctl show` looks healthy
- [ ] `kernel: hci0: ACL packet for unknown connection handle` in journal

**Did `modprobe -r btusb btmtk && modprobe btusb` recover it (same MAC, no re-pair)?** yes / no / not tried

**Did `systemctl restart bluetooth` recover it?** yes / no / not tried

**Paste**: `journalctl -k --since "-1h"` around the incident (and `btmon` capture if you have one — gold).

**Optional gold**: during the failure, did a phone-side BLE scanner (nRF Connect) see the peripheral advertising? yes / no / not tried
