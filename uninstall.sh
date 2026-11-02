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
RENDER=$LIB_DIR/maneuver_render
ATLAS=$LIB_DIR/flag_atlas.rgba
BLANK=$LIB_DIR/rgd_blank.png
SHADER_DIR=$LIB_DIR/shaders
SUPERVISOR=$LIB_DIR/rgd_render_sup.sh
SBIN=/mnt/app/armle/usr/sbin
# Releases up to 2026-09-19 drew maneuvers from pre-drawn pictures kept here.
FRAMES_DIR=$LIB_DIR/rgd_frames

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
            *LD_PRELOAD*libcarplay_hook.so*"]"*)
                head=${line%%", \"LD_PRELOAD"*}
                echo "$head]," >> "$NEW"
                ;;
            *LD_PRELOAD*libcarplay_hook.so*,)
                # An array written one entry per line (see install.sh).
                head=${line%%" \"LD_PRELOAD"*}
                echo "$head" >> "$NEW"
                ;;
            *LD_PRELOAD*libcarplay_hook.so*)
                head=${line%%", \"LD_PRELOAD"*}
                echo "$head" >> "$NEW"
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
# Beside it and then over it, as install.sh puts the shim in: a running
# mm-ipod keeps the file busy, and writing into it fails with "cannot create".
restore_mm_ipod() {
    cp "$1" "$SBIN/mm-ipod.new" && chmod 755 "$SBIN/mm-ipod.new" \
        && mv "$SBIN/mm-ipod.new" "$SBIN/mm-ipod"
}
if [ -f "$SBIN/mm-ipod.orig" ]; then
    restore_mm_ipod "$SBIN/mm-ipod.orig" \
        && say "restored $SBIN/mm-ipod from .orig" \
        || say "!! could not restore $SBIN/mm-ipod - do it by hand"
elif [ -f "$SBIN/rgd_real/mm-ipod" ]; then
    restore_mm_ipod "$SBIN/rgd_real/mm-ipod" \
        && say "restored $SBIN/mm-ipod from rgd_real/" \
        || say "!! could not restore $SBIN/mm-ipod - do it by hand"
else
    say "no shim installed - nothing to undo"
fi

# The supervisor goes before the renderer it starts, so nothing restarts it
# between the two.  Anything already running keeps running until the reboot
# this script ends by asking for.
for f in "$SUPERVISOR" "$RENDER" "$ATLAS" "$BLANK" "$RGD_JAR" "$RGD_SO"; do
    if [ -f "$f" ]; then
        rm -f "$f" && say "removed: $f" || say "!! could not remove $f"
    fi
done

if [ -d "$SHADER_DIR" ]; then
    rm -f "$SHADER_DIR"/*.bin 2>/dev/null
    # The unit has no rmdir, and its rm needs -r for a directory.
    rm -r "$SHADER_DIR" 2>/dev/null
    say "removed: $SHADER_DIR"
fi

# Left behind by a release that drew maneuvers from pre-drawn pictures: about
# 90 MB of PNGs in three sets.  Explicit paths and explicit file names, never
# "rm -rf $VAR" - one empty variable there would take the whole lib directory.
if [ -d "$FRAMES_DIR" ]; then
    for stage in small large large_sport; do
        [ -d "$FRAMES_DIR/$stage" ] || continue
        rm -f "$FRAMES_DIR/$stage"/*.png "$FRAMES_DIR/$stage"/frames.idx 2>/dev/null
        rm -r "$FRAMES_DIR/$stage" 2>/dev/null
    done
    rm -r "$FRAMES_DIR" 2>/dev/null
    say "removed: $FRAMES_DIR"
fi

# Markers the patches read.  rgd_disable is the user's own off switch; taking
# it away with the patch is right - there is nothing left for it to disable.
rm -f /mnt/app/rgd_disable /mnt/app/rgd_cluster_ctx /mnt/app/rgd_rgtype \
      /mnt/app/rgd_sport /mnt/app/rgd_hook.log /mnt/app/rgd_render.log \
      /mnt/app/rgd_render_hold /mnt/app/rgd_no_tel /mnt/app/rgd_eta_default /mnt/app/rgd_map_only "$LIB_DIR/.rgd_render_hold_set" 2>/dev/null

# The CarPlay map in the cluster: its renderer, supervisor, shaders, its on
# switch and the steering-wheel choice.
for f in "$LIB_DIR/altscreen_render" "$LIB_DIR/altscreen_sup.sh"; do
    [ -f "$f" ] && { rm -f "$f" && say "removed: $f" || say "!! could not remove $f"; }
done
if [ -d "$LIB_DIR/altscreen_shaders" ]; then
    rm -f "$LIB_DIR/altscreen_shaders"/*.bin 2>/dev/null
    rm -r "$LIB_DIR/altscreen_shaders" 2>/dev/null
    say "removed: $LIB_DIR/altscreen_shaders"
fi
rm -f /mnt/app/altscreen_inject /mnt/app/altscreen_force /mnt/app/altscreen_cluster_off \
      /mnt/app/altscreen_render.log /mnt/app/altscreen_probe.log 2>/dev/null

say ""
say "--- removing files ---"
for f in "$JARS_DIR/coverart_hook.jar" "$JARS_DIR/dpad_hook.jar" "$JARS_DIR/pdc_hook.jar" \
         /mnt/app/eso/hmi/lsd/images/HMIEarlyAppsEvoHighScale/2199999.png "$SO_DEST"; do
    if [ -f "$f" ]; then
        rm -f "$f" && say "removed: $f" || say "!! could not remove $f"
    else
        say "not present: $f"
    fi
done

# M.I.B.'s NavActiveIgnore, if the installer switched it off: back as it was.
for f in "$JARS_DIR"/*.carplay-off; do
    [ -f "$f" ] || continue
    mv "$f" "${f%.carplay-off}" && say "switched back on: ${f%.carplay-off}" \
        || say "!! could not restore ${f%.carplay-off}"
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
