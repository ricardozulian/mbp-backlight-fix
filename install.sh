#!/bin/bash
# Install MacBookPro11,3 gmux backlight fix. Run as root (pkexec/sudo).
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
GRUB_FILE="${GRUB_FILE:-/etc/default/grub}"

if [ "$(id -u)" -ne 0 ]; then
    echo "install.sh must run as root (try: pkexec $SRC/install.sh)" >&2
    exit 1
fi

install -d -m 0755 /usr/local/sbin /var/lib/mbp-backlight /etc/xdg/autostart /usr/share/gdm/greeter/autostart
install -m 0755 "$SRC/sbin/mbp-gmux-bridge.sh" /usr/local/sbin/mbp-gmux-bridge.sh
install -m 0755 "$SRC/sbin/mbp-backlight" /usr/local/sbin/mbp-backlight
install -m 0755 "$SRC/sbin/mbp-backlight-watch" /usr/local/sbin/mbp-backlight-watch
install -m 0755 "$SRC/sbin/mbp-session-blank" /usr/local/sbin/mbp-session-blank
install -m 0755 "$SRC/sbin/mbp-system-blank" /usr/local/sbin/mbp-system-blank
install -m 0644 "$SRC/systemd/mbp-gmux-bridge.service" /etc/systemd/system/mbp-gmux-bridge.service
install -m 0644 "$SRC/systemd/mbp-backlight-watch.service" /etc/systemd/system/mbp-backlight-watch.service
install -m 0644 "$SRC/systemd/mbp-system-blank.service" /etc/systemd/system/mbp-system-blank.service
install -m 0644 "$SRC/udev/99-mbp-gmux-backlight.rules" /etc/udev/rules.d/99-mbp-gmux-backlight.rules
install -m 0644 "$SRC/autostart/mbp-session-blank.desktop" /etc/xdg/autostart/mbp-session-blank.desktop
install -m 0644 "$SRC/autostart/mbp-session-blank-greeter.desktop" /usr/share/gdm/greeter/autostart/mbp-session-blank.desktop
install -m 0644 "$SRC/default/mbp-backlight" /etc/default/mbp-backlight

product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
if [ "$product" != "MacBookPro11,3" ]; then
    echo "warning: developed for MacBookPro11,3 (this machine: ${product:-unknown})" >&2
fi

TARGET_USER="${SUDO_USER:-}"
if [ -n "${PKEXEC_UID:-}" ]; then
    TARGET_USER="$(getent passwd "$PKEXEC_UID" | cut -d: -f1 || true)"
fi
if [ -z "${TARGET_USER:-}" ] || [ "$TARGET_USER" = "root" ]; then
    TARGET_USER="$(loginctl list-users --no-legend 2>/dev/null | awk '$1 >= 1000 { print $2; exit }')"
fi
if [ -n "${TARGET_USER:-}" ] && getent group video >/dev/null && getent passwd "$TARGET_USER" >/dev/null; then
    usermod -aG video "$TARGET_USER" || true
fi

if [ "${1:-}" = "--blacklist-i915" ]; then
    install -m 0644 "$SRC/modprobe/blacklist-i915-mbp.conf" /etc/modprobe.d/blacklist-i915-mbp.conf
    if command -v update-initramfs >/dev/null 2>&1; then
        update-initramfs -u || true
    fi
    echo "installed i915 blacklist"
fi

GDM_CONF=/etc/gdm3/custom.conf
if [ -f "$GDM_CONF" ]; then
    if grep -qE '^WaylandEnable=false' "$GDM_CONF"; then
        echo "GDM already has WaylandEnable=false"
    elif grep -qE '^#WaylandEnable=false' "$GDM_CONF"; then
        sed -i 's/^#WaylandEnable=false/WaylandEnable=false/' "$GDM_CONF"
        echo "GDM greeter forced to Xorg (WaylandEnable=false)"
    elif grep -qE '^\[daemon\]' "$GDM_CONF"; then
        sed -i '/^\[daemon\]/a WaylandEnable=false' "$GDM_CONF"
        echo "GDM greeter forced to Xorg (WaylandEnable=false)"
    fi
fi

# Kernel cmdline: gmux must register the backlight class device.
if [ -f "$GRUB_FILE" ]; then
    cp -a "$GRUB_FILE" "$GRUB_FILE.mbp-backlight.bak"
    python3 - "$GRUB_FILE" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
orig = text

def rewrite(match):
    quote = match.group(1)
    value = match.group(2)
    parts = value.split()
    kept = [p for p in parts if not p.startswith("acpi_backlight=") and p != "acpi_osi=linux"]
    if "acpi_backlight=apple_gmux" not in kept:
        kept.append("acpi_backlight=apple_gmux")
    return f'GRUB_CMDLINE_LINUX_DEFAULT={quote}{" ".join(kept)}{quote}'

new, n = re.subn(
    r'^GRUB_CMDLINE_LINUX_DEFAULT=(["\'])(.*)(["\'])\s*$',
    rewrite,
    text,
    count=1,
    flags=re.M,
)
if n != 1:
    sys.stderr.write("install.sh: could not rewrite GRUB_CMDLINE_LINUX_DEFAULT\n")
    sys.exit(1)
if new != orig:
    open(path, "w", encoding="utf-8").write(new)
    print(f"updated {path}")
else:
    print(f"{path} already has the desired cmdline")
PY
    if command -v update-grub >/dev/null 2>&1; then
        update-grub
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        grub-mkconfig -o /boot/grub/grub.cfg
    else
        echo "install.sh: grub tools not found; kernel cmdline was edited but not generated" >&2
        exit 1
    fi
else
    echo "install.sh: $GRUB_FILE missing" >&2
    exit 1
fi

systemctl daemon-reload
systemctl enable mbp-gmux-bridge.service mbp-backlight-watch.service mbp-system-blank.service
# Apply the PCI quirk now so a later live test can work; the watch service
# stays idle until gmux_backlight appears (after reboot).
systemctl start mbp-gmux-bridge.service || true
systemctl start mbp-backlight-watch.service || true
systemctl start mbp-system-blank.service || true
udevadm control --reload || true

echo
echo "Installed. Reboot is required so apple-gmux registers gmux_backlight."
echo "If you also need the DKMS overlay: sudo $SRC/install-dkms.sh"
echo "After reboot, verify:"
echo "  ls /sys/class/backlight"
echo "  cat /sys/class/backlight/gmux_backlight/{type,max_brightness,brightness}"
echo "  systemctl status mbp-gmux-bridge mbp-backlight-watch mbp-system-blank"
