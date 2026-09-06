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
LIB_DIR=/mnt/app/eso/hmi/lib
SO_DEST=$LIB_DIR/libcarplay_hook.so
CFG=/mnt/system/etc/eso/production/smartphone_integrator.json
LOG=/tmp/carplay_uninstall.log

# Route guidance (RGI)
RGD_SO=$LIB_DIR/librgd_hook.so
RGD_JAR=$JARS_DIR/rgd_hook.jar
FRAMES_DIR=$LIB_DIR/rgd_frames
SBIN=/mnt/app/armle/usr/sbin

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
# ---------------------------------------------------------------- route guidance
# The shim goes first, for the same reason the config did: if anything below
# fails, the unit still starts a stock mm-ipod with nothing preloaded.
say ""
say "--- route guidance (RGI) ---"
if [ -f "$SBIN/mm-ipod.orig" ]; then
    cat "$SBIN/mm-ipod.orig" > "$SBIN/mm-ipod" && chmod 755 "$SBIN/mm-ipod" \
        && say "restored $SBIN/mm-ipod from .orig" \
        || say "!! could not restore $SBIN/mm-ipod - do it by hand"
elif [ -f "$SBIN/rgd_real/mm-ipod" ]; then
    cat "$SBIN/rgd_real/mm-ipod" > "$SBIN/mm-ipod" && chmod 755 "$SBIN/mm-ipod" \
        && say "restored $SBIN/mm-ipod from rgd_real/" \
        || say "!! could not restore $SBIN/mm-ipod - do it by hand"
else
    say "no shim installed - nothing to undo"
fi

for f in "$RGD_JAR" "$RGD_SO"; do
    if [ -f "$f" ]; then
        rm -f "$f" && say "removed: $f" || say "!! could not remove $f"
    fi
done

if [ -d "$FRAMES_DIR" ]; then
    # No `rm -rf` on a directory tree here: the unit's rm has it, but the frame
    # set is 3600 files and one wrong variable would take the lot with it.
    # Explicit paths only.
    for stage in small large; do
        [ -d "$FRAMES_DIR/$stage" ] || continue
        rm -f "$FRAMES_DIR/$stage"/*.png "$FRAMES_DIR/$stage"/frames.idx 2>/dev/null
        rmdir "$FRAMES_DIR/$stage" 2>/dev/null
    done
    rmdir "$FRAMES_DIR" 2>/dev/null
    say "removed: $FRAMES_DIR"
fi

# Markers the feature reads.  rgd_disable is the user's own off switch; taking
# it away with the patch is right - there is nothing left for it to disable.
rm -f /mnt/app/rgd_disable /mnt/app/rgd_cluster_ctx /mnt/app/rgd_rgtype \
      /mnt/app/rgd_hook.log 2>/dev/null

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
