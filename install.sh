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
#   3. Copies the jars into the HMI's jar directory and the native hooks
#      into /mnt/app/eso/hmi/lib.
#   4. Adds LD_PRELOAD for the cover-art hook to the carplay child in
#      smartphone_integrator.json - line-based, no sed (the unit has none).
#   5. Installs route guidance (RGI): the maneuver frames, the RGI jar, and a
#      shim in front of mm-ipod that preloads its hook.  Skip it with RGI=0.
#   6. Tells you to reboot.
#
# Everything is idempotent: running it twice changes nothing the second time.
# POSIX sh only - no bashisms, and none of sed, awk or dirname: the unit
# has no such utilities.

set -u

JARS_DIR=/mnt/app/eso/hmi/lsd/jars
LIB_DIR=/mnt/app/eso/hmi/lib
SO_DEST=$LIB_DIR/libcarplay_hook.so
CFG=/mnt/system/etc/eso/production/smartphone_integrator.json
LOG=/tmp/carplay_install.log

# Route guidance (RGI).  RGI=0 leaves the whole feature out of the install;
# everything else here is unaffected either way.
RGI=${RGI:-1}
RGD_SO=$LIB_DIR/librgd_hook.so
RGD_JAR=$JARS_DIR/rgd_hook.jar
FRAMES_DIR=$LIB_DIR/rgd_frames
SBIN=/mnt/app/armle/usr/sbin
# Frames need about 35 MB; refuse rather than half-fill the partition.
FRAMES_KB_NEEDED=40000

# No `dirname` either - see the note in custom.sh.  ${0%/*} strips the last
# /component, but leaves $0 untouched when it has no slash at all, so the
# no-slash case has to pick "." explicitly.
if [ -z "${SRC_DIR:-}" ]; then
    case $0 in
        */*) SRC_DIR=${0%/*} ;;
        *)   SRC_DIR=. ;;
    esac
fi
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
say "payload: $BIN_DIR"

# ---------------------------------------------------------------- payload
for f in coverart_hook.jar dpad_hook.jar libcarplay_hook.so; do
    [ -f "$BIN_DIR/$f" ] || die "missing payload file: $BIN_DIR/$f"
done

if [ "$RGI" != "0" ]; then
    for f in rgd_hook.jar librgd_hook.so; do
        [ -f "$BIN_DIR/$f" ] || die "missing payload file: $BIN_DIR/$f (or set RGI=0)"
    done
    [ -f "$BIN_DIR/rgd_frames/small/frames.idx" ] || \
        die "missing maneuver frames: $BIN_DIR/rgd_frames (or set RGI=0)"
    say "route guidance: ON (RGI=0 skips it)"
else
    say "route guidance: SKIPPED (RGI=0)"
fi

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

# The hook goes in via rename, not a plain cp over the top. On an upgrade
# dio_manager may be running right now with the old .so mapped, and writing
# through that file would be modifying a live process image. rename() swaps
# the directory entry instead: the running process keeps the inode it mapped
# and picks up the new one when it is next started.
cp "$BIN_DIR/libcarplay_hook.so" "$SO_DEST.new" || die "copy libcarplay_hook.so failed"
chmod 755 "$SO_DEST.new"
mv "$SO_DEST.new" "$SO_DEST" || die "could not put libcarplay_hook.so in place"

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

# NOTE: do NOT test for LD_PRELOAD across the whole file. Stock already has one,
# on a different child ("LD_PRELOAD=/eso/lib/libsystemtime_hack.so"), so a
# file-wide test always says "already patched" and the hook silently never
# gets preloaded. The only question that matters is whether OUR entry is on
# the carplay child's env line.
if grep "libcarplay_hook.so" "$CFG" > /dev/null 2>&1; then
    say "our LD_PRELOAD is already on the carplay child - leaving the config alone"
else
    NEW=$CFG.new
    : > "$NEW" || die "cannot write $NEW"
    HITS=0
    CONFLICT=0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *IPL_CONFIG_DIR_DIO_MANAGER*)
                HITS=$((HITS + 1))
                case "$line" in
                    *LD_PRELOAD*)
                        # Someone else already preloads into dio_manager. Two
                        # LD_PRELOAD entries in one array is not something to
                        # guess at - stop and let a human look.
                        CONFLICT=1
                        echo "$line" >> "$NEW"
                        ;;
                    *)
                        head=${line%%"]"*}
                        echo "$head, \"LD_PRELOAD=$SO_DEST\"]," >> "$NEW"
                        ;;
                esac
                ;;
            *)
                echo "$line" >> "$NEW"
                ;;
        esac
    done < "$CFG"

    if [ "$HITS" != "1" ]; then
        rm -f "$NEW"
        die "expected exactly 1 carplay env line, found $HITS - config not touched"
    fi
    if [ "$CONFLICT" = "1" ]; then
        rm -f "$NEW"
        die "the carplay child already has an LD_PRELOAD of its own - config not touched, add ours by hand"
    fi
    grep "libcarplay_hook.so" "$NEW" > /dev/null 2>&1 || {
        rm -f "$NEW"
        die "patched config does not contain the hook - config not touched"
    }

    # Write through the existing file rather than replacing it, so the config
    # keeps its own mode and owner whatever they are. If this ever fails
    # half-way the stock file is still at $CFG.orig.
    cat "$NEW" > "$CFG" || die "could not write $CFG (backup is at $CFG.orig)"
    rm -f "$NEW"
    say "ok: LD_PRELOAD=$SO_DEST added to the carplay child"
fi

# ---------------------------------------------------------------- route guidance
if [ "$RGI" != "0" ]; then
    say ""
    say "--- route guidance (RGI) ---"

    # Frames are ~3600 small PNGs.  The unit has no tar, gzip or unzip, so they
    # travel as plain files and are copied with cp; check there is room first.
    FREE=`df -k "$LIB_DIR" 2>/dev/null | tail -1`
    set -- $FREE
    # df -k prints: filesystem 1K-blocks used available capacity mounted
    AVAIL=$4
    case "$AVAIL" in
        ''|*[!0-9]*) say "note: could not read free space, continuing" ;;
        *) [ "$AVAIL" -lt "$FRAMES_KB_NEEDED" ] && \
               die "only ${AVAIL}K free on /mnt/app, the frames need ${FRAMES_KB_NEEDED}K" ;;
    esac

    cp "$BIN_DIR/rgd_hook.jar" "$RGD_JAR" || die "copy rgd_hook.jar failed"
    chmod 755 "$RGD_JAR"
    say "ok: $RGD_JAR"

    cp "$BIN_DIR/librgd_hook.so" "$RGD_SO.new" || die "copy librgd_hook.so failed"
    chmod 755 "$RGD_SO.new"
    mv "$RGD_SO.new" "$RGD_SO" || die "could not put librgd_hook.so in place"
    say "ok: $RGD_SO"

    for stage in small large; do
        [ -d "$FRAMES_DIR/$stage" ] || mkdir -p "$FRAMES_DIR/$stage" || \
            die "could not create $FRAMES_DIR/$stage"
        say "copying $stage frames (this takes a minute)..."
        cp "$BIN_DIR/rgd_frames/$stage"/* "$FRAMES_DIR/$stage/" || \
            die "copying $stage frames failed"
        chmod 644 "$FRAMES_DIR/$stage"/* 2>/dev/null
    done
    say "ok: $FRAMES_DIR"

    # The shim.  mm-ipod is started by usblauncher out of a config on flash,
    # which we do not touch; instead the binary on /mnt/app is replaced by a
    # script that preloads the hook and execs the real one.  The real binary
    # keeps the name mm-ipod under rgd_real/, because the hook gates on
    # argv[0]'s basename.
    if [ ! -f "$SBIN/mm-ipod" ]; then
        die "$SBIN/mm-ipod not found - unexpected firmware layout"
    fi
    if [ ! -f "$SBIN/rgd_real/mm-ipod" ]; then
        mkdir -p "$SBIN/rgd_real" || die "could not create $SBIN/rgd_real"
        cp -p "$SBIN/mm-ipod" "$SBIN/rgd_real/mm-ipod" || die "could not copy mm-ipod aside"
        cp -p "$SBIN/mm-ipod" "$SBIN/mm-ipod.orig" || die "could not back up mm-ipod"
        say "saved the original mm-ipod ($SBIN/mm-ipod.orig)"
    else
        say "shim already installed - refreshing it"
    fi

    cat > "$SBIN/mm-ipod.new" <<'SHIM'
#!/bin/sh
# Route-guidance shim.  The real binary is in rgd_real/ under its own name so
# argv[0] stays "mm-ipod" - the hook gates on that.
# Off switch: touch /mnt/app/rgd_disable, then replug the phone.
[ -f /mnt/app/rgd_disable ] || LD_PRELOAD=/mnt/app/eso/hmi/lib/librgd_hook.so
export LD_PRELOAD
exec /mnt/app/armle/usr/sbin/rgd_real/mm-ipod "$@"
SHIM
    chmod 755 "$SBIN/mm-ipod.new"
    mv "$SBIN/mm-ipod.new" "$SBIN/mm-ipod" || die "could not install the shim"
    say "ok: $SBIN/mm-ipod (shim)"
fi

# ---------------------------------------------------------------- done
say ""
say "--- installed files ---"
ls -l "$JARS_DIR/dpad_hook.jar" "$JARS_DIR/coverart_hook.jar" "$SO_DEST" 2>&1 | while IFS= read -r l; do say "$l"; done
if [ "$RGI" != "0" ]; then
    ls -l "$RGD_JAR" "$RGD_SO" "$SBIN/mm-ipod" 2>&1 | while IFS= read -r l; do say "$l"; done
fi

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
if [ "$RGI" != "0" ]; then
    say ""
    say "Route guidance is installed and on.  Start a route in Apple Maps or"
    say "Google Maps on the phone and the maneuver appears in the cluster."
    say "To turn it off later, without uninstalling anything:"
    say "  touch /mnt/app/rgd_disable   (then reboot)"
    say "and to turn it back on, delete that file and reboot."
fi
say ""
say "This log: $LOG"
