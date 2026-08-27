#!/bin/sh
# Unstick gmux backlight writes on MacBookPro11,3.
# The NVIDIA upstream bridge's VGA-forwarding bits can block gmux PWM updates.
set -eu

PCI_DEV="${MBP_GMUX_BRIDGE:-00:01.0}"

if ! command -v setpci >/dev/null 2>&1; then
    echo "mbp-gmux-bridge: setpci not found" >&2
    exit 1
fi

# -H1: type-1 PCI config access, as required by the historical MBP 11,3 quirk.
before="$(setpci -s "$PCI_DEV" BRIDGE_CONTROL 2>/dev/null || true)"
setpci -v -H1 -s "$PCI_DEV" BRIDGE_CONTROL=0
after="$(setpci -s "$PCI_DEV" BRIDGE_CONTROL 2>/dev/null || true)"
echo "mbp-gmux-bridge: $PCI_DEV BRIDGE_CONTROL ${before:-?} -> ${after:-?}"
