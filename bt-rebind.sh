#!/bin/bash
# MT79xx BT driver rebind - the proven reset path (same as Framework KB)
modprobe -r btusb btmtk 2>/dev/null
sleep 1
modprobe btusb
