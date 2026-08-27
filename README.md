# MacBookPro11,3 Linux backlight fix

On the dual-GPU **MacBookPro11,3** (Retina 15", Late 2013) Linux can blank the
panel while the **backlight PWM stays on**. You get a glowing black screen on
idle, lid-close, DPMS, and the GDM login screen.

This repo turns the PWM off with the screen, and back on when the panel wakes.
It is meant to work **from boot** (GDM greeter) as well as after login.

Verified on Ubuntu 24.04, Cinnamon/X11, kernels 6.14 and 7.0, EFI `simpledrm`
(no NVIDIA/nouveau modeset).

## Hardware

| | |
| --- | --- |
| Machine | `MacBookPro11,3` |
| CPU | Intel Core i7-4870HQ (Haswell / Crystal Well) |
| dGPU | NVIDIA GK107M GeForce GT 750M (Mac Edition) |
| iGPU | Intel Iris Pro 5200 (EFI GOP usually stays on the dGPU) |
| Panel PWM | Apple **gmux** (indexed, v4.0.8) → TI LP8545/LP8548 |

The GPU does not generate backlight PWM on this dual-GPU Retina. Brightness is
owned by gmux (`APP000B`, I/O `0x700`).

Not for T2 or Apple Silicon Macs.

## Why stock Linux fails

1. **No `/sys/class/backlight` device.**  
   `acpi_backlight=vendor` makes `apple-gmux` skip `gmux_backlight`. The old
   `apple_bl` driver cannot program this panel, so sysfs is empty.

2. **DPMS does not program gmux.**  
   `simpledrm` stops scanout. PWM stays at the EFI-saved level (~200–400 of
   1023). Cinnamon/GDM also set X DPMS Off timeouts to 0 and call gnome-rr,
   which fails on the `None-1` output, so the connector never goes `dpms=Off`.

3. **`BRIDGE_CONTROL` quirk.** Gmux writes are ignored until:

   ```sh
   setpci -v -H1 -s 00:01.0 BRIDGE_CONTROL=0
   ```

4. **Kernel 7.0+ iGPU.** If `i915` binds, X opens a second modeset device next
   to `simpledrm` and unblank fights itself. Optional: blacklist `i915`.

5. **GDM Wayland greeter.** Default Ubuntu GDM runs mutter as a Wayland
   compositor on `simpledrm`. There is no Xorg until you log in, so `xset`
   never runs on the login screen. The greeter can look black while PWM stays
   on. `install.sh` sets `WaylandEnable=false` (Xorg greeter), and
   `mbp-backlight-watch` also turns PWM off after the configured **input idle**
   time even if DRM DPMS never changes.

## What gets installed

| Piece | When | Role |
| --- | --- | --- |
| `acpi_backlight=apple_gmux` | boot | Let gmux own brightness |
| DKMS `mbp-apple-gmux` | boot | Always register `gmux_backlight` |
| `mbp-gmux-bridge.service` | boot | `BRIDGE_CONTROL=0` |
| `mbp-backlight-watch.service` | boot | PWM 0 when DRM DPMS is Off, the lid is closed, or keyboard/mouse/trackpad idle exceeds the timeout |
| `mbp-system-blank.service` | boot | Set X DPMS Off on **every** X server, including GDM |
| `mbp-session-blank` | GDM greeter + user session | Extra DPMS helper after login |
| udev rule | boot | `video` group can write gmux sysfs |
| optional `blacklist i915` | boot | Single `simpledrm` device |

The PWM watcher only acts on **transitions**. It does not force the backlight
on at login.

## Install

Ubuntu/Debian. Needs `python3`, `pciutils` (`setpci`), `x11-xserver-utils`
(`xset`), and for the DKMS overlay: `dkms`, `build-essential`,
`linux-headers-$(uname -r)`.

```sh
sudo apt install python3 pciutils x11-xserver-utils dkms build-essential linux-headers-$(uname -r)
sudo ./install.sh
sudo ./install-dkms.sh
sudo reboot
```

If kernel 7.0+ enumerates the Intel GPU and the desktop keeps unblanking:

```sh
sudo ./install.sh --blacklist-i915
sudo reboot
```

Timeouts (GDM + session) are in `/etc/default/mbp-backlight`:

```
DPMS_OFF_AC=600
DPMS_OFF_BATTERY=300
```

## Verify after reboot

```sh
cat /proc/cmdline                    # acpi_backlight=apple_gmux
ls /sys/class/backlight              # gmux_backlight
cat /sys/class/backlight/gmux_backlight/{type,max_brightness,actual_brightness,bl_power}
# type=platform  max=1023  bl_power=0

lsmod | grep i915                    # empty if you blacklisted it
ls /sys/class/drm                    # card0 + card0-Unknown-1

systemctl is-enabled --now \
  mbp-gmux-bridge.service \
  mbp-backlight-watch.service \
  mbp-system-blank.service

DISPLAY=:0 xset q | grep -A2 '^  Standby'
# Off: 600 (AC) or 300 (battery)
```

Idle (10 min on AC) and lid-close should leave a **fully dark** panel, including
on the GDM prompt before login. A key or mouse move restores brightness.

Do **not** test with `xset dpms force off` on an active Cinnamon session.
Cinnamon will unblank immediately. Use real idle or lid-close.

Manual PWM check (dims the screen):

```sh
old=$(cat /sys/class/backlight/gmux_backlight/actual_brightness)
echo 0 | sudo tee /sys/class/backlight/gmux_backlight/brightness
echo 4 | sudo tee /sys/class/backlight/gmux_backlight/bl_power
# LEDs off
echo 0 | sudo tee /sys/class/backlight/gmux_backlight/bl_power
echo "$old" | sudo tee /sys/class/backlight/gmux_backlight/brightness
```

## Layout

```
install.sh / install-dkms.sh / uninstall.sh
sbin/mbp-gmux-bridge.sh          # setpci quirk
sbin/mbp-backlight               # on / off / status / save
sbin/mbp-backlight-watch         # PWM vs DRM DPMS + lid (root, from boot)
sbin/mbp-system-blank            # X DPMS on all X servers (root, from boot)
sbin/mbp-session-blank           # X DPMS in a graphical session
systemd/*.service
autostart/*.desktop              # Cinnamon session + GDM greeter
udev/99-mbp-gmux-backlight.rules
modprobe/blacklist-i915-mbp.conf
default/mbp-backlight            # DPMS_OFF_AC / DPMS_OFF_BATTERY
dkms/apple-gmux.c                # Linux 6.14 apple-gmux + always-register
dkms/Makefile
dkms/dkms.conf                   # mbp-apple-gmux/1.0
```

## Kernel patch

Upstream only registers the backlight when

```c
acpi_video_get_backlight_type() == acpi_backlight_apple_gmux
```

`acpi_backlight=vendor` makes that false. The DKMS copy forces
`register_bdev = true`. `nouveau` already logs `Apple GMUX detected: not
registering Nouveau backlight interface` and stands down; do not make i915 or
nouveau own PWM on this machine.

## Uninstall

```sh
sudo ./uninstall.sh
sudo reboot
```

## License

GPL-2.0-only. `dkms/apple-gmux.c` is the in-tree Linux driver (see its header)
plus a small local change. See [LICENSE](LICENSE).
