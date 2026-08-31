#!/bin/sh
#
# custom.sh - M.I.B. entry point.
#
# Copy this file to /mod/custom.sh on the M.I.B. SD card and the rest of this
# repository to /mod/carplay/, then on the unit:
#
#     Advanced Settings -> Run Custom Script
#
# It finds the payload on the card and runs install.sh. To uninstall instead,
# create an empty file named UNINSTALL next to install.sh on the card
# (/mod/carplay/UNINSTALL) and run the custom script again.

set -u

echo "=== MHI2 AU37x CarPlay patches - M.I.B. launcher ==="

# The card can be mounted under different names depending on the reader, so
# look for our payload rather than assuming a path.
PAYLOAD=""
for d in \
    "$(dirname "$0")/carplay" \
    /fs/sda0/mod/carplay /fs/sda1/mod/carplay \
    /fs/mmc0/mod/carplay /fs/mmc1/mod/carplay \
    /mnt/sda0/mod/carplay /mnt/mmc0/mod/carplay
do
    if [ -f "$d/install.sh" ] && [ -f "$d/bin/libcarplay_hook.so" ]; then
        PAYLOAD=$d
        break
    fi
done

if [ -z "$PAYLOAD" ]; then
    echo "  (not in the usual places, searching the card - may take a minute)"
    for d in $(find /fs /mnt -maxdepth 4 -type d -name carplay 2>/dev/null); do
        if [ -f "$d/install.sh" ] && [ -f "$d/bin/libcarplay_hook.so" ]; then
            PAYLOAD=$d
            break
        fi
    done
fi

if [ -z "$PAYLOAD" ]; then
    echo "!! payload not found."
    echo "!! Expected /mod/carplay/install.sh and /mod/carplay/bin/ on the card."
    exit 1
fi

echo "payload: $PAYLOAD"

if [ -f "$PAYLOAD/UNINSTALL" ]; then
    echo "UNINSTALL marker present - removing the patches"
    SRC_DIR="$PAYLOAD" sh "$PAYLOAD/uninstall.sh"
else
    SRC_DIR="$PAYLOAD" sh "$PAYLOAD/install.sh"
fi

echo ""
echo "Read the log above, then reboot the unit."
