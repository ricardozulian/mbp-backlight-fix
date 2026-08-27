#!/bin/bash
# Remove the MacBookPro gmux backlight fix. Run as root.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "uninstall.sh must run as root (try: sudo $0)" >&2
    exit 1
fi

systemctl disable --now mbp-system-blank.service mbp-backlight-watch.service mbp-gmux-bridge.service 2>/dev/null || true

if command -v dkms >/dev/null 2>&1; then
    dkms remove mbp-apple-gmux/1.0 --all 2>/dev/null || true
fi
rm -rf /usr/src/mbp-apple-gmux-1.0

rm -f /usr/local/sbin/mbp-backlight \
      /usr/local/sbin/mbp-backlight-watch \
      /usr/local/sbin/mbp-gmux-bridge.sh \
      /usr/local/sbin/mbp-session-blank \
      /usr/local/sbin/mbp-system-blank \
      /etc/systemd/system/mbp-backlight-watch.service \
      /etc/systemd/system/mbp-gmux-bridge.service \
      /etc/systemd/system/mbp-system-blank.service \
      /etc/udev/rules.d/99-mbp-gmux-backlight.rules \
      /etc/modprobe.d/blacklist-i915-mbp.conf \
      /etc/xdg/autostart/mbp-session-blank.desktop \
      /usr/share/gdm/greeter/autostart/mbp-session-blank.desktop \
      /etc/default/mbp-backlight

systemctl daemon-reload || true
udevadm control --reload || true

GRUB_FILE="${GRUB_FILE:-/etc/default/grub}"
if [ -f "$GRUB_FILE.mbp-backlight.bak" ]; then
    echo "Restoring $GRUB_FILE from ${GRUB_FILE}.mbp-backlight.bak"
    cp -a "$GRUB_FILE.mbp-backlight.bak" "$GRUB_FILE"
    if command -v update-grub >/dev/null 2>&1; then
        update-grub
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        grub-mkconfig -o /boot/grub/grub.cfg
    fi
else
    echo "No GRUB backup found. Remove acpi_backlight=apple_gmux from $GRUB_FILE yourself if you added it."
fi

echo "Uninstalled. Reboot to unload the DKMS module and restore the stock apple-gmux."
