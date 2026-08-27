#!/bin/bash
# Build and install the patched apple-gmux DKMS module.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
NAME=mbp-apple-gmux
VER=1.0
DEST="/usr/src/${NAME}-${VER}"
KVER="${KVER:-$(uname -r)}"

if [ "$(id -u)" -ne 0 ]; then
    echo "install-dkms.sh must run as root (try: sudo $SRC/install-dkms.sh)" >&2
    exit 1
fi

if ! command -v dkms >/dev/null 2>&1; then
    echo "dkms is not installed (apt install dkms build-essential linux-headers-$(uname -r))" >&2
    exit 1
fi
if [ ! -d "/lib/modules/${KVER}/build" ]; then
    echo "kernel headers for ${KVER} are missing (/lib/modules/${KVER}/build)" >&2
    echo "apt install linux-headers-${KVER}" >&2
    exit 1
fi

rm -rf "$DEST"
mkdir -p "$DEST"
install -m 0644 "$SRC/dkms/apple-gmux.c" "$SRC/dkms/Makefile" "$SRC/dkms/dkms.conf" "$DEST/"

if dkms status -m "$NAME" -v "$VER" 2>/dev/null | grep -q .; then
    dkms remove -m "$NAME" -v "$VER" --all || true
fi

dkms add -m "$NAME" -v "$VER"
dkms build -m "$NAME" -v "$VER" -k "$KVER"
dkms install -m "$NAME" -v "$VER" -k "$KVER"
dkms status -m "$NAME"
modinfo apple_gmux | grep -E 'filename|vermagic|srcversion'
echo
echo "DKMS module installed. Reboot (or: modprobe -r apple_gmux && modprobe apple_gmux)"
echo "to load it if the in-tree module is already bound."
