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
# replace_cfg SRC - put SRC's content in place of the config.  Built in a copy
# made with cp -p, so it keeps the config's own mode and owner, and renamed
# over it: the config is either the old file or the whole new one.
replace_cfg() {
    cp -p "$CFG" "$CFG.new" && cat "$1" > "$CFG.new" && mv "$CFG.new" "$CFG" && return 0
    rm -f "$CFG.new"
    return 1
}

# strip_cfg - take our LD_PRELOAD entry off the carplay child's env line,
# line-based.  Only our entry, never the stock LD_PRELOAD on the other child.
strip_cfg() {
    TMP=$CFG.strip
    : > "$TMP" || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *LD_PRELOAD*libcarplay_hook.so*"]"*)
                # Whatever followed our entry is kept: the bracket and, on
                # stock, the comma after it.
                head=${line%%", \"LD_PRELOAD"*}
                tail=${line##*"libcarplay_hook.so\""}
                echo "$head$tail" >> "$TMP"
                ;;
            *LD_PRELOAD*libcarplay_hook.so*,)
                # An array written one entry per line (see install.sh).
                head=${line%%" \"LD_PRELOAD"*}
                echo "$head" >> "$TMP"
                ;;
            *LD_PRELOAD*libcarplay_hook.so*)
                head=${line%%", \"LD_PRELOAD"*}
                echo "$head" >> "$TMP"
                ;;
            *)
                echo "$line" >> "$TMP"
                ;;
        esac
    done < "$CFG"
    if grep "libcarplay_hook.so" "$TMP" > /dev/null 2>&1; then
        rm -f "$TMP"
        return 1
    fi
    replace_cfg "$TMP"
    rc=$?
    rm -f "$TMP"
    return $rc
}

if [ -f "$CFG.orig" ]; then
    replace_cfg "$CFG.orig" && say "restored from $CFG.orig" \
        || say "!! could not restore $CFG - do it by hand"
fi
# Also after a restore: a backup taken from a config that already carried the
# hook (added by hand before the first install) puts the hook straight back,
# and the library it names is deleted below.
if grep "libcarplay_hook.so" "$CFG" > /dev/null 2>&1; then
    strip_cfg && say "LD_PRELOAD removed" \
        || say "!! could not strip LD_PRELOAD automatically - edit $CFG by hand"
elif [ ! -f "$CFG.orig" ]; then
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
      /mnt/app/rgd_render_hold /mnt/app/rgd_no_tel /mnt/app/rgd_eta_default /mnt/app/rgd_map_only "$LIB_DIR/.rgd_render_hold_set" \
      /mnt/app/rgd_no_arrow_fill /mnt/app/rgd_rearm /mnt/app/rgd_maps30 /mnt/app/pdc_log \
      /mnt/app/rgd_hook.log.prev /mnt/app/carplay_hook.log \
      /mnt/app/.mhi2_trace /mnt/app/.mhi2_trace_keep /mnt/app/.mhi2_trace_all 2>/dev/null

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
      /mnt/app/altscreen_render.log /mnt/app/altscreen_probe.log \
      /mnt/app/altscreen_sw /mnt/app/altscreen_url /mnt/app/altscreen_toggle_key 2>/dev/null

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
