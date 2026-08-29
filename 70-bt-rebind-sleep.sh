#!/bin/sh
# Rebind BT driver on resume (systemd-sleep post phase; suspend.target units do NOT fire)
[ "$1" = "post" ] && (modprobe -r btusb btmtk 2>/dev/null; modprobe btusb)
exit 0
