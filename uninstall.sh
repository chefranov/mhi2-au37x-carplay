#!/bin/sh
#
# uninstall.sh - removes the MHI2 AU37x CarPlay patches, back to stock.
#
# Runs on the head unit (QNX 6.5 /bin/sh), same two ways as install.sh.
# Safe to run at any time, including when only part of the install landed.
#
# Order matters: the config goes back first, so that even if something below
# fails the unit boots a stock dio_manager with no LD_PRELOAD.

set -u

JARS_DIR=/mnt/app/eso/hmi/lsd/jars
SO_DEST=/mnt/app/eso/hmi/lib/libcarplay_hook.so
CFG=/mnt/system/etc/eso/production/smartphone_integrator.json
LOG=/tmp/carplay_uninstall.log

say() {
    echo "$@"
    echo "$@" >> "$LOG" 2>/dev/null
}

: > "$LOG" 2>/dev/null
say "=== MHI2 AU37x CarPlay patches - uninstall ==="

mount -uw /mnt/app 2>/dev/null
mount -uw /mnt/system 2>/dev/null

# ---------------------------------------------------------------- config
say ""
say "--- smartphone_integrator.json ---"
if [ -f "$CFG.orig" ]; then
    # cat, not cp: writes through the existing file so its mode and owner
    # stay exactly as the unit had them.
    cat "$CFG.orig" > "$CFG" && say "restored from $CFG.orig" \
        || say "!! could not restore $CFG - do it by hand"
elif grep "libcarplay_hook.so" "$CFG" > /dev/null 2>&1; then
    # No backup (installed by hand?). Strip our entry line-based instead.
    NEW=$CFG.new
    : > "$NEW"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *LD_PRELOAD*libcarplay_hook.so*)
                head=${line%%", \"LD_PRELOAD"*}
                echo "$head]," >> "$NEW"
                ;;
            *)
                echo "$line" >> "$NEW"
                ;;
        esac
    done < "$CFG"
    # Only our entry, never the stock LD_PRELOAD on the other child.
    if grep "libcarplay_hook.so" "$NEW" > /dev/null 2>&1; then
        rm -f "$NEW"
        say "!! could not strip LD_PRELOAD automatically - edit $CFG by hand"
    else
        cat "$NEW" > "$CFG" && say "LD_PRELOAD removed"
        rm -f "$NEW"
    fi
else
    say "no LD_PRELOAD in the config - nothing to undo"
fi

# ---------------------------------------------------------------- files
say ""
say "--- removing files ---"
for f in "$JARS_DIR/coverart_hook.jar" "$JARS_DIR/dpad_hook.jar" "$SO_DEST"; do
    if [ -f "$f" ]; then
        rm -f "$f" && say "removed: $f" || say "!! could not remove $f"
    else
        say "not present: $f"
    fi
done

say ""
say "--- flushing writes ---"
sync
sleep 2
sync

say ""
say "=== DONE - REBOOT to come up stock ==="
say "The .orig backup is left in place on purpose; delete it yourself if you"
say "want no trace: rm $CFG.orig"
say "This log: $LOG"
