#!/usr/bin/env bash
# Full reverse of install.sh
set -e
systemctl --user disable --now bt-watch 2>/dev/null || true
rm -f ~/.config/systemd/user/bt-watch.service ~/.local/bin/bt-watch.sh
systemctl --user daemon-reload
sudo rm -f /etc/sudoers.d/bt-rebind /usr/local/bin/bt-rebind.sh
sudo rm -f /etc/udev/rules.d/99-btusb-no-autosuspend.rules
sudo rm -f /usr/lib/systemd/system-sleep/70-bt-rebind.sh
echo "Uninstalled (USB autosuspend is back to kernel default; reboot to fully apply)."
