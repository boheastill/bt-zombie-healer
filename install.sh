#!/usr/bin/env bash
# One-shot installer (run as your normal user; sudo is asked for privileged parts)
set -e
cd "$(dirname "$0")"

# Guard: only install on machines with a MediaTek BT adapter
if ! lsusb | grep -qiE '13d3|0e8d|0489'; then
  echo "No MediaTek Bluetooth adapter detected (USB IDs 13d3/0e8d/0489). This tool targets MT79xx — aborting."
  exit 1
fi

sudo install -m 755 bt-rebind.sh /usr/local/bin/bt-rebind.sh
echo "$USER ALL=(root) NOPASSWD: /usr/local/bin/bt-rebind.sh" | sudo tee /etc/sudoers.d/bt-rebind >/dev/null
sudo chmod 440 /etc/sudoers.d/bt-rebind
sudo visudo -cf /etc/sudoers.d/bt-rebind

# udev: disable USB autosuspend for the MT79xx BT part (find it by looking for Wireless_Device / btusb)
for d in /sys/bus/usb/devices/*/idVendor; do
  dev=$(dirname "$d")
  if ls "$dev" 2>/dev/null | grep -q ':1.0' && cat "$dev/product" 2>/dev/null | grep -qi wireless; then
    vid=$(cat "$dev/idVendor"); pid=$(cat "$dev/idProduct")
    echo "ACTION==\"add\", SUBSYSTEM==\"usb\", ATTR{idVendor}=\"$vid\", ATTR{idProduct}=\"$pid\", ATTR{power/control}=\"on\"" | \
      sudo tee /etc/udev/rules.d/99-btusb-no-autosuspend.rules >/dev/null
    echo "udev rule written for $vid:$pid"
    break
  fi
done

sudo install -m 755 70-bt-rebind-sleep.sh /usr/lib/systemd/system-sleep/70-bt-rebind.sh

mkdir -p ~/.local/bin ~/.config/systemd/user
install -m 755 bt-watch.sh ~/.local/bin/bt-watch.sh
cat > ~/.config/systemd/user/bt-watch.service <<EOF
[Unit]
Description=Bluetooth zombie-state watchdog (bt-zombie-healer)
[Service]
ExecStart=$HOME/.local/bin/bt-watch.sh
Restart=always
RestartSec=10
[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload && systemctl --user enable --now bt-watch

echo "Installed. Watchdog active: systemctl --user status bt-watch"
echo "Test the reset path anytime: sudo /usr/local/bin/bt-rebind.sh"
