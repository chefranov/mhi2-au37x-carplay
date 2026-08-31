#!/bin/sh
#
# install.sh - installs the MHI2 AU37x CarPlay patches ON THE UNIT.
#
# Runs on the head unit itself (QNX 6.5 /bin/sh) - either over ssh/telnet
# after copying this directory across, or from the SD card via M.I.B.
# (Advanced Settings -> Run Custom Script; see custom.sh).
#
# What it does:
#   1. Remounts /mnt/app and /mnt/system read-write.
#   2. Backs up every file it is going to change, once, as <file>.orig.
#   3. Copies the two jars into the HMI's jar directory and the native hook
#      into /mnt/app/eso/hmi/lib.
#   4. Adds LD_PRELOAD for the hook to the carplay child in
#      smartphone_integrator.json - line-based, no sed (the unit has none).
#   5. Tells you to reboot.
#
# Everything is idempotent: running it twice changes nothing the second time.
# POSIX sh only - no bashisms, no sed, no awk.

set -u

JARS_DIR=/mnt/app/eso/hmi/lsd/jars
LIB_DIR=/mnt/app/eso/hmi/lib
SO_DEST=$LIB_DIR/libcarplay_hook.so
CFG=/mnt/system/etc/eso/production/smartphone_integrator.json
LOG=/tmp/carplay_install.log

SRC_DIR=${SRC_DIR:-$(dirname "$0")}
BIN_DIR=$SRC_DIR/bin

say() {
    echo "$@"
    echo "$@" >> "$LOG" 2>/dev/null
}

die() {
    say "!! $*"
    say "!! ABORTED - nothing further was changed."
    exit 1
}

: > "$LOG" 2>/dev/null
say "=== MHI2 AU37x CarPlay patches - install ==="
say "date: $(date 2>/dev/null)"
say "payload: $BIN_DIR"

# ---------------------------------------------------------------- payload
for f in coverart_hook.jar dpad_hook.jar libcarplay_hook.so; do
    [ -f "$BIN_DIR/$f" ] || die "missing payload file: $BIN_DIR/$f"
done

# ---------------------------------------------------------------- unit check
[ -d /mnt/app/eso ] || die "/mnt/app/eso not found - this is not an MHI2 unit"
[ -f "$CFG" ] || die "$CFG not found - unexpected firmware layout, stopping"

if [ ! -f /mnt/app/armle/usr/lib/libiap2client.so.1 ]; then
    say "!! WARNING: libiap2client.so.1 not found."
    say "!! Cover art needs the HARMAN iAP2 stack. The DPAD patch is unaffected."
fi

# ---------------------------------------------------------------- writable
say ""
say "--- remounting partitions read-write ---"
mount -uw /mnt/app 2>/dev/null
mount -uw /mnt/system 2>/dev/null
touch /mnt/app/.rwtest 2>/dev/null || die "/mnt/app is not writable"
rm -f /mnt/app/.rwtest
touch /mnt/system/.rwtest 2>/dev/null || die "/mnt/system is not writable"
rm -f /mnt/system/.rwtest
say "ok: /mnt/app and /mnt/system are writable"

# ---------------------------------------------------------------- backup
backup_once() {
    if [ -f "$1" ] && [ ! -f "$1.orig" ]; then
        cp -p "$1" "$1.orig" || die "could not back up $1"
        say "backed up: $1 -> $1.orig"
    elif [ -f "$1.orig" ]; then
        say "backup already present: $1.orig (kept, not overwritten)"
    fi
}

say ""
say "--- backups ---"
backup_once "$CFG"
# The jars and the .so are new files - nothing stock is replaced, so an
# uninstall is just deleting them again.

# ---------------------------------------------------------------- copy
say ""
say "--- copying files ---"
[ -d "$JARS_DIR" ] || mkdir -p "$JARS_DIR" || die "could not create $JARS_DIR"
[ -d "$LIB_DIR" ] || mkdir -p "$LIB_DIR" || die "could not create $LIB_DIR"

cp "$BIN_DIR/dpad_hook.jar" "$JARS_DIR/dpad_hook.jar" || die "copy dpad_hook.jar failed"
cp "$BIN_DIR/coverart_hook.jar" "$JARS_DIR/coverart_hook.jar" || die "copy coverart_hook.jar failed"
cp "$BIN_DIR/libcarplay_hook.so" "$SO_DEST" || die "copy libcarplay_hook.so failed"

# Set the modes explicitly. cp gives whatever the umask and the source
# filesystem happen to produce - and on the M.I.B. path the source is a FAT32
# card, which carries no Unix modes at all. Every stock file in the jars
# directory is world-readable (-rwxrwxrwx root:root), so an unreadable jar
# would simply be skipped by lsd with no error anywhere.
chmod 755 "$JARS_DIR/dpad_hook.jar" "$JARS_DIR/coverart_hook.jar" "$SO_DEST"

say "ok: $JARS_DIR/dpad_hook.jar"
say "ok: $JARS_DIR/coverart_hook.jar"
say "ok: $SO_DEST"

# ---------------------------------------------------------------- config
# The carplay child's env line is unique in the file:
#   "envs":["LD_LIBRARY_PATH=...", "IPL_CONFIG_DIR_DIO_MANAGER=/etc/eso/production"],
# We append our LD_PRELOAD to that array. Line-based, because the unit has no
# sed and no awk; the file is written one key per line, so this is safe.
say ""
say "--- smartphone_integrator.json ---"

if grep LD_PRELOAD "$CFG" > /dev/null 2>&1; then
    say "LD_PRELOAD already present - leaving the config alone"
else
    NEW=$CFG.new
    : > "$NEW" || die "cannot write $NEW"
    HITS=0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *IPL_CONFIG_DIR_DIO_MANAGER*)
                head=${line%%"]"*}
                printf '%s, "LD_PRELOAD=%s"],\n' "$head" "$SO_DEST" >> "$NEW"
                HITS=$((HITS + 1))
                ;;
            *)
                printf '%s\n' "$line" >> "$NEW"
                ;;
        esac
    done < "$CFG"

    if [ "$HITS" != "1" ]; then
        rm -f "$NEW"
        die "expected exactly 1 carplay env line, found $HITS - config not touched"
    fi
    grep LD_PRELOAD "$NEW" > /dev/null 2>&1 || {
        rm -f "$NEW"
        die "patched config has no LD_PRELOAD - config not touched"
    }

    # Write through the existing file rather than replacing it, so the config
    # keeps its own mode and owner whatever they are. If this ever fails
    # half-way the stock file is still at $CFG.orig.
    cat "$NEW" > "$CFG" || die "could not write $CFG (backup is at $CFG.orig)"
    rm -f "$NEW"
    say "ok: LD_PRELOAD=$SO_DEST added to the carplay child"
fi

# ---------------------------------------------------------------- done
say ""
say "--- installed files ---"
ls -l "$JARS_DIR/dpad_hook.jar" "$JARS_DIR/coverart_hook.jar" "$SO_DEST" 2>&1 | while IFS= read -r l; do say "$l"; done

say ""
say "--- flushing writes ---"
sync
sleep 2
sync

say ""
say "=== DONE ==="
say "REBOOT the unit for the patches to load."
say "Wait a few seconds first - the writes above must reach flash."
say ""
say "After the reboot, plug in an iPhone and check:"
say "  cat /tmp/carplay_hook.log"
say ""
say "This log: $LOG"
