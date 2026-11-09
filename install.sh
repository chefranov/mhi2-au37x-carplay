#!/bin/sh
#
# install.sh - installs the MHI2 AU37x CarPlay patches ON THE UNIT.
#
# Runs on the head unit itself (QNX 6.5 /bin/sh) - either over ssh/telnet
# after copying this directory across, or from the SD card via M.I.B.
# (Advanced Settings -> Run Custom Script; see custom.sh).
#
# What it does:
#   0. Checks the firmware train and stops, changing nothing, on anything
#      that is not MHI2_*_AU37x_* or MHI2_*_AU276_* (Audi Q2), on AU37x
#      ER builds up to P3242 (too old), or when another CarPlay/HMI mod is
#      on the unit (MIBSI, mib2q-carplay-rgi, unknown jars;
#      IGNORE_CONFLICTS=1 lets unknown jars through).
#      M.I.B.'s NavActiveIgnore jar is switched off, uninstall puts it back.
#   1. Remounts /mnt/app and /mnt/system read-write.
#   2. Backs up every file it is going to change, once, as <file>.orig.
#   3. Copies the jars into the HMI's jar directory (D-pad, cover art, and, on
#      firmware it was checked against, the parking-sensor popup beside CarPlay)
#      and the native hooks into /mnt/app/eso/hmi/lib.
#   4. Adds LD_PRELOAD for the cover-art hook to the carplay child in
#      smartphone_integrator.json - line-based, no sed (the unit has none).
#   5. Installs route guidance (RGI): the RGI jar, the cluster renderer with its
#      compiled shaders, and a shim in front of mm-ipod that preloads the hook
#      and starts the renderer's supervisor.  Skip it with RGI=0.
#   6. Installs the CarPlay map in the cluster (AltScreen): its renderer, the
#      renderer's compiled shaders and supervisor, and the marker that turns
#      it on.  Needs route guidance; skip it alone with ALTSCREEN=0.
#   7. Removes the pre-drawn maneuver frames, if an older install left them.
#   8. Undoes a part left out this time (RGI=0, ALTSCREEN=0) that an earlier
#      install put there, and drops files earlier releases used and this one
#      does not.
#   9. Tells you to reboot.
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
RENDER=$LIB_DIR/maneuver_render
ATLAS=$LIB_DIR/flag_atlas.rgba
BLANK=$LIB_DIR/rgd_blank.png
SHADER_DIR=$LIB_DIR/shaders
SUPERVISOR=$LIB_DIR/rgd_render_sup.sh
SBIN=/mnt/app/armle/usr/sbin
# Releases up to 2026-09-19 shipped ~5400 pre-drawn PNGs here, about 90 MB of
# them. The renderer replaced the lot, so an upgrade deletes them.
FRAMES_DIR=$LIB_DIR/rgd_frames
SHADERS="main.vert main.frag fxaa.vert fxaa.frag"

# The CarPlay map in the cluster.  Rides on route guidance (the jar declares its
# cluster context, the route-guidance supervisor starts its renderer), so
# RGI=0 leaves it out too.  ALTSCREEN=0 leaves out only this.
ALTSCREEN=${ALTSCREEN:-1}
[ "$RGI" = "0" ] && ALTSCREEN=0
ALT_RENDER=$LIB_DIR/altscreen_render
ALT_SUP=$LIB_DIR/altscreen_sup.sh
ALT_SHADER_DIR=$LIB_DIR/altscreen_shaders
ALT_SHADERS="main.vert video.frag intro.frag"
ALT_ON=/mnt/app/altscreen_inject
# Offer the cluster screen to a wireless adapter that does not ask for it (the
# Carlinkit 2Air, #25).  Opt-in: an adapter that cannot handle a second screen
# may take it for its main one.  WIRELESS_MAP=1 (an empty WIRELESS_MAP file on
# the card) switches it on; every other install switches it off again.
WIRELESS_MAP=${WIRELESS_MAP:-0}
ALT_FORCE=/mnt/app/altscreen_force

# The parking-sensor popup beside CarPlay replaces seven stock HMI classes, and
# other firmware carries other versions of them: on CN P0916 the HMI never came
# up (#27), on Q2 P5600 two of them differ too, and forcing it onto such
# firmware is what kept leaving units on the start logo.  So it is off unless
# asked for: PDC=1 (an empty PDC file on the card) installs it, and only on
# firmware whose classes were checked against it.  Left out, an earlier copy is
# removed.
PDC=${PDC:-0}

# Force the sport cluster layout (1) or the classic one (0). Unset means "leave
# whatever is already there", which is what an upgrade wants.
SPORT=${SPORT:-}

# Start the line under the maneuver on the arrival time (1) or on the next
# street (0); a short press of the left roller swaps them either way.  Unset
# leaves what is there, as with SPORT.
ETA_DEFAULT=${ETA_DEFAULT:-}

# Keep the CarPlay map in the cluster but leave route guidance to the phone's
# own screen (1): no maneuver tile, no takeover of the cluster's route fields
# (#22, #38).  Unset leaves what is there, as with SPORT.
MAP_ONLY=${MAP_ONLY:-}

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
if [ -f "$SRC_DIR/VERSION" ]; then
    read -r VERSION < "$SRC_DIR/VERSION"
    say "release: $VERSION"
fi

# ---------------------------------------------------------------- unit check
[ -d /mnt/app/eso ] || die "/mnt/app/eso not found - this is not an MHI2 unit"
[ -f "$CFG" ] || die "$CFG not found - unexpected firmware layout, stopping"

# The firmware train.  The jars replace stock HMI classes outright, and other
# trains carry other versions of them: on MHI2_US_AUG22 neither the D-pad nor
# route guidance even compiles, and on the unit that is a black main screen.
# So anything that is not MHI2_*_AU37x_* stops here, before a single write.
# MHI2_*_AU276_* (Audi Q2) is let through: its HMI classes are identical, and
# the release is confirmed working on a Q2.
#
# Two sources, the way M.I.B. reads them.  First the text file the software
# update leaves on rcc's persist partition; then the EEPROM, 19 bytes at 0x3A0,
# through modifyE2P on rcc.  The unit has no xxd, sed, tr or printf, so the
# EEPROM bytes are compared as hex: "MHI2_" at 0..4, "_AU37x_" or "_AU276_"
# at 7..13, the build ("P3242") at 14..18.  A trailing CR in the text file
# is harmless: the pattern ends in *.
#
# European AU37x builds up to P3242 are older than the HMI classes replaced
# here and are refused (TRAIN_OK=2).  P3242: compared against its lsd.jxe
# (#70), the D-pad and route guidance do not compile - its ClusterService and
# CarPlay input controller predate classes and constants they call.  P3620
# works (#64); what lies between is unknown and let through.  Build numbers
# are per region (CN P0817 and P1003 work), so only ER builds are compared.
ER_OLDEST_OK=3243

# er_build_too_old NNNN - true when the four digits are an ER build that
# predates ER_OLDEST_OK.  Anything that is not four digits is not judged.
er_build_too_old() {
    case "$1" in
        [0-9][0-9][0-9][0-9]) [ "$1" -lt "$ER_OLDEST_OK" ] ;;
        *) return 1 ;;
    esac
}

# The ER build number from the EEPROM bytes: region "ER" at 5..6 (45 52),
# "P" at 14 (50), four ASCII digits at 15..18 (3x).  Prints nothing otherwise.
er_build_from_hex() {
    set -- $1
    [ $# -ge 19 ] || return 0
    case "$6 $7 ${15}" in "45 52 50") ;; *) return 0 ;; esac
    _n=""
    for _b in "${16}" "${17}" "${18}" "${19}"; do
        case "$_b" in 3[0-9]) _n="$_n${_b#3}" ;; *) return 0 ;; esac
    done
    echo "$_n"
}
TRAIN=""
for f in /net/rcc/mnt/efs-persist/SWDL/CachedTrain.txt /mnt/efs-persist/SWDL/CachedTrain.txt; do
    if [ -f "$f" ]; then
        read -r TRAIN < "$f"
        break
    fi
done

TRAIN_OK=""
case "$TRAIN" in
    MHI2_ER_AU37[xX]_P[0-9][0-9][0-9][0-9]*)
        ER_BUILD=${TRAIN#MHI2_ER_AU37?_P}; ER_BUILD=${ER_BUILD%"${ER_BUILD#????}"}
        if er_build_too_old "$ER_BUILD"; then TRAIN_OK=2; else TRAIN_OK=1; fi ;;
    MHI2_*_AU37[xX]_*|MHI2_*_AU276_*) TRAIN_OK=1 ;;
    "") ;;
    *) TRAIN_OK=0 ;;
esac

if [ -z "$TRAIN_OK" ]; then
    HEX=""
    for tok in $(on -f rcc /net/rcc/usr/apps/modifyE2P r 3A0 19 2>/dev/null); do
        case "$tok" in
            [0-9a-fA-F][0-9a-fA-F]) HEX="$HEX $tok" ;;
        esac
    done
    case "$HEX" in
        " 4"[dD]" 48 49 32 5"[fF]" "??" "??" 5"[fF]" 41 55 33 37 "[57]"8 5"[fF]*)
            ER_BUILD=$(er_build_from_hex "$HEX")
            if er_build_too_old "$ER_BUILD"; then
                TRAIN_OK=2; TRAIN="MHI2_ER_AU37x_P$ER_BUILD (from EEPROM)"
            else
                TRAIN_OK=1; TRAIN="MHI2_??_AU37x_* (from EEPROM)"
            fi ;;
        " 4"[dD]" 48 49 32 5"[fF]" "??" "??" 5"[fF]" 41 55 32 37 36 5"[fF]*)
            TRAIN_OK=1; TRAIN="MHI2_??_AU276_* (from EEPROM)" ;;
        "") ;;
        *) TRAIN_OK=0; TRAIN="(EEPROM bytes:$HEX)" ;;
    esac
fi

case "$TRAIN_OK" in
    1) say "firmware train: $TRAIN - ok" ;;
    0) say "!! firmware train: $TRAIN"
       say "!! These patches are for MHI2_*_AU37x_* and MHI2_*_AU276_* firmware only."
       say "!! They replace stock HMI classes of that firmware, and on another train"
       say "!! they can leave the main screen black. See"
       say "!! https://github.com/chefranov/mhi2-au37x-carplay/wiki/Compatibility"
       die "unsupported firmware train" ;;
    2) say "!! firmware train: $TRAIN"
       say "!! This AU37x build is older than the HMI classes these patches replace:"
       say "!! the D-pad and route guidance do not match it, and installing would most"
       say "!! likely keep the MMI from starting. Update the firmware first (P5089 is"
       say "!! the tested build). See"
       say "!! https://github.com/chefranov/mhi2-au37x-carplay/wiki/Compatibility"
       die "firmware build too old" ;;
    *) say "!! could not read the firmware train (no CachedTrain.txt, no EEPROM answer)."
       say "!! Installing without knowing it is how a black main screen happens."
       say "!! Please open an issue and attach this log."
       die "firmware train unknown" ;;
esac

# ---------------------------------------------------------------- payload
say "payload: $BIN_DIR"
for f in coverart_hook.jar dpad_hook.jar libcarplay_hook.so; do
    [ -f "$BIN_DIR/$f" ] || die "missing payload file: $BIN_DIR/$f"
done

if [ "$RGI" != "0" ]; then
    for f in rgd_hook.jar librgd_hook.so; do
        [ -f "$BIN_DIR/$f" ] || die "missing payload file: $BIN_DIR/$f (or set RGI=0)"
    done
    for f in maneuver_render flag_atlas.rgba rgd_blank.png; do
        [ -f "$BIN_DIR/$f" ] || die "missing payload file: $BIN_DIR/$f (or set RGI=0)"
    done
    for s in $SHADERS; do
        [ -f "$BIN_DIR/shaders/$s.bin" ] || \
            die "missing compiled shader: $BIN_DIR/shaders/$s.bin (or set RGI=0)"
    done
    say "route guidance: ON (RGI=0 skips it)"
    if [ "$ALTSCREEN" != "0" ]; then
        for f in altscreen_render altscreen_sup.sh; do
            [ -f "$BIN_DIR/$f" ] || die "missing payload file: $BIN_DIR/$f (or set ALTSCREEN=0)"
        done
        for s in $ALT_SHADERS; do
            [ -f "$BIN_DIR/altscreen_shaders/$s.bin" ] || \
                die "missing compiled shader: $BIN_DIR/altscreen_shaders/$s.bin (or set ALTSCREEN=0)"
        done
        say "CarPlay map in the cluster: ON (ALTSCREEN=0 skips it)"
    else
        say "CarPlay map in the cluster: SKIPPED"
    fi
else
    say "route guidance: SKIPPED (RGI=0)"
fi

if [ "$PDC" = "1" ]; then
    case "$TRAIN" in
        MHI2_ER_AU37[xX]_P5089*|MHI2_ER_AU276_P5088*) ;;
        *) PDC=0
           say "parking popup beside CarPlay: not checked on this firmware - left out" ;;
    esac
else
    PDC=0
    say "parking popup beside CarPlay: off (PDC=1 installs it on P5089 / Q2 P5088)"
fi
if [ "$PDC" = "1" ] && [ ! -f "$BIN_DIR/pdc_hook.jar" ]; then
    die "missing payload file: $BIN_DIR/pdc_hook.jar (or set PDC=0)"
fi

if [ ! -f /mnt/app/armle/usr/lib/libiap2client.so.1 ]; then
    say "!! WARNING: libiap2client.so.1 not found."
    say "!! Cover art needs the HARMAN iAP2 stack. The DPAD patch is unaffected."
fi

# ---------------------------------------------------------------- other mods
# Other CarPlay and cluster mods replace the same stock HMI classes, or the same
# processes (dio_manager, mm-ipod, the iAP2 driver).  Two of them on one unit is
# how the main screen goes black: whichever jar the HMI loads first wins, and a
# mix of two versions of one class can keep the HMI from starting at all.  So
# look before writing anything, and stop on what is known to clash.
#
# Jars nobody here recognises stop the install too, because a black screen is
# the price of guessing wrong.  IGNORE_CONFLICTS=1 (an empty IGNORE_CONFLICTS
# file on the card) lets them through; it does not override the known clashes.
IGNORE_CONFLICTS=${IGNORE_CONFLICTS:-0}
LSD_SH=/mnt/app/eso/hmi/lsd/lsd.sh
[ -f "$LSD_SH" ] || LSD_SH=/eso/hmi/lsd/lsd.sh
CONFLICT=0
NAVIGNORE=""
UNKNOWN=""

say ""
say "--- other mods ---"

# MIBSI: replaces dio_manager, gal, the iAP2 driver and lsd.sh, and keeps its
# files under directories named after itself.
for d in /mnt/app/root/mibsi-* /eso/lib/mibsi-* /mnt/app/eso/lib/mibsi-* /eso/mibsi-*; do
    if [ -e "$d" ]; then
        say "!! MIBSI is installed ($d)."
        say "!!   Remove it with its own uninstall card first, then run this again."
        CONFLICT=1
        break
    fi
done

# Anything put on the HMI classpath ahead of the stock jars.  Stock lsd.sh only
# ever appends to BOOTCLASSPATH; a line that prepends is somebody's mod.
if [ -f "$LSD_SH" ] && grep -q -e 'BOOTCLASSPATH="/' -e '/mnt/app/root/' "$LSD_SH"; then
    say "!! $LSD_SH has been changed: it puts other code on the HMI classpath."
    say "!!   Uninstall whatever changed it first (MIBSI does this)."
    CONFLICT=1
fi

# mib2q-carplay-rgi and its forks: their own startup hooks and a patched
# smartphone_integrator.
if [ -f /mnt/app/root/hooks/carplay_startup.sh ] || \
   [ -f /mnt/app/eso/bin/apps/smartphone_integrator.carplay-stock ]; then
    say "!! Another CarPlay mod is installed (mib2q-carplay-rgi or a fork, /mnt/app/root/hooks/)."
    say "!!   Uninstall it first."
    CONFLICT=1
fi

# A wrapper in front of mm-ipod that is not ours.  Ours keeps the real binary
# in rgd_real/; without that directory mm-ipod must still be the stock binary.
# grep finds nothing in a binary on this unit, which is exactly the test.
if [ "$RGI" != "0" ] && [ ! -f "$SBIN/rgd_real/mm-ipod" ] && \
   grep -q '^#!' "$SBIN/mm-ipod" 2>/dev/null; then
    say "!! $SBIN/mm-ipod is a script, not the stock binary - another mod wraps it."
    say "!!   Uninstall that mod first, or install with RGI=0 (NO_RGI on the card)."
    CONFLICT=1
fi

# Somebody else's LD_PRELOAD on the carplay child, i.e. inside dio_manager.  The
# config step below refuses this too, but by then the jars are already copied;
# asking here leaves the unit untouched.
if ! grep "libcarplay_hook.so" "$CFG" > /dev/null 2>&1; then
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            *IPL_CONFIG_DIR_DIO_MANAGER*LD_PRELOAD*|*LD_PRELOAD*IPL_CONFIG_DIR_DIO_MANAGER*)
                say "!! dio_manager already has an LD_PRELOAD of its own in $CFG:"
                say "!!   $line"
                say "!!   Another mod hooks into CarPlay. Uninstall it first."
                CONFLICT=1
                ;;
        esac
    done < "$CFG"
fi

# The jars the HMI loads.  lsd.sh puts every *.jar and *.zip in this directory
# on the classpath, so the names say what is there.
for j in "$JARS_DIR"/*.jar "$JARS_DIR"/*.zip; do
    [ -f "$j" ] || continue
    n=${j##*/}
    case "$n" in
        AppDevelopment.jar|DevelopmentStubEvo.jar|RemoteHMI-Libs-Ext.jar|diag.jar|\
        lang_data.zip|locale.zip|xEventRecorder.jar|xEventRecorderEvo.jar|\
        xTcpKeyPanel.jar|xTcpLog.jar)
            ;;  # stock
        dpad_hook.jar|coverart_hook.jar|rgd_hook.jar|pdc_hook.jar|vehdata_hook.jar)
            ;;  # this project
        NavActiveIgnore.jar|navignore_audi.jar|navignore_vw.jar)
            NAVIGNORE="$NAVIGNORE $n" ;;
        carplay_hook.jar|carplay_hook_cn.jar)
            say "!! $n is another CarPlay mod (mib2q-carplay-rgi or a fork). Uninstall it first."
            CONFLICT=1 ;;
        mhi2-*-hmi-prototype.jar|mhi2-*-vc-bridge.jar)
            say "!! $n belongs to MIBSI. Uninstall MIBSI first."
            CONFLICT=1 ;;
        *)
            UNKNOWN="$UNKNOWN $n" ;;
    esac
done

if [ -n "$UNKNOWN" ]; then
    say "!! Jars this installer does not know, in $JARS_DIR:"
    for n in $UNKNOWN; do say "!!   $n"; done
    if [ "$IGNORE_CONFLICTS" = "1" ]; then
        say "!! IGNORE_CONFLICTS is set - going on anyway."
    else
        say "!!   If they are another HMI or CarPlay mod, uninstall it first."
        say "!!   If you know they are harmless, run again with IGNORE_CONFLICTS=1"
        say "!!   (or an empty IGNORE_CONFLICTS file next to install.sh on the card)."
        CONFLICT=1
    fi
fi

[ "$CONFLICT" = "0" ] || die "another mod is in the way - see above"

# M.I.B.'s NavActiveIgnore replaces org.dsi.ifc.carplay.AppState so that every
# app state and owner reads 0, and the HMI loses track of what CarPlay owns.
# It is switched off further down by a rename that lsd.sh no longer picks up;
# uninstall.sh puts it back.
if [ -n "$NAVIGNORE" ]; then
    say "M.I.B. NavActiveIgnore found:$NAVIGNORE - it will be switched off (uninstall puts it back)"
else
    say "ok: no other mods found"
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

for n in $NAVIGNORE; do
    mv "$JARS_DIR/$n" "$JARS_DIR/$n.carplay-off" || die "could not switch off $JARS_DIR/$n"
    say "switched off: $JARS_DIR/$n -> $n.carplay-off"
done
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
# The sensors popup's background without the black strip under its frame,
# used only over CarPlay. Only the 800-px HMI has it (AU37x); elsewhere the
# directory is missing and the stock background stays.
PDC_BG_DIR=/mnt/app/eso/hmi/lsd/images/HMIEarlyAppsEvoHighScale
if [ "$PDC" = "1" ]; then
    cp "$BIN_DIR/pdc_hook.jar" "$JARS_DIR/pdc_hook.jar" || die "copy pdc_hook.jar failed"
    chmod 755 "$JARS_DIR/pdc_hook.jar"
    say "ok: $JARS_DIR/pdc_hook.jar"
    if [ -d "$PDC_BG_DIR" ] && [ -f "$BIN_DIR/2199999.png" ]; then
        cp "$BIN_DIR/2199999.png" "$PDC_BG_DIR/2199999.png" && chmod 644 "$PDC_BG_DIR/2199999.png" \
            && say "ok: $PDC_BG_DIR/2199999.png" || say "!! could not copy the parking popup background"
    fi
else
    if [ -f "$JARS_DIR/pdc_hook.jar" ]; then
        rm -f "$JARS_DIR/pdc_hook.jar" && say "removed: $JARS_DIR/pdc_hook.jar (parking popup left out)" \
            || say "!! could not remove $JARS_DIR/pdc_hook.jar"
    fi
    rm -f "$PDC_BG_DIR/2199999.png" 2>/dev/null
fi
say "ok: $SO_DEST"

# ---------------------------------------------------------------- config
# The carplay child's env line is unique in the file:
#   "envs":["LD_LIBRARY_PATH=...", "IPL_CONFIG_DIR_DIO_MANAGER=/etc/eso/production"],
# We append our LD_PRELOAD to that array. Line-based, because the unit has no
# sed and no awk; the file is written one key per line, so this is safe.
# Should the array be written one entry per line, the IPL entry last and the
# closing bracket on a line of its own, the entry goes after it with no
# bracket.
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
                    *"]"*)
                        head=${line%%"]"*}
                        echo "$head, \"LD_PRELOAD=$SO_DEST\"]," >> "$NEW"
                        ;;
                    *,)
                        echo "$line \"LD_PRELOAD=$SO_DEST\"," >> "$NEW"
                        ;;
                    *)
                        echo "$line, \"LD_PRELOAD=$SO_DEST\"" >> "$NEW"
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

    cp "$BIN_DIR/rgd_hook.jar" "$RGD_JAR" || die "copy rgd_hook.jar failed"
    chmod 755 "$RGD_JAR"
    say "ok: $RGD_JAR"

    cp "$BIN_DIR/librgd_hook.so" "$RGD_SO.new" || die "copy librgd_hook.so failed"
    chmod 755 "$RGD_SO.new"
    mv "$RGD_SO.new" "$RGD_SO" || die "could not put librgd_hook.so in place"
    say "ok: $RGD_SO"

    # The renderer. A process of its own: it draws the maneuver live into a
    # window of its own that the cluster composites over the head unit's map,
    # and the jar above tells it what to draw.
    cp "$BIN_DIR/maneuver_render" "$RENDER.new" || die "copy maneuver_render failed"
    chmod 755 "$RENDER.new"
    mv "$RENDER.new" "$RENDER" || die "could not put maneuver_render in place"
    say "ok: $RENDER"

    cp "$BIN_DIR/flag_atlas.rgba" "$ATLAS" || die "copy flag_atlas.rgba failed"
    cp "$BIN_DIR/rgd_blank.png" "$BLANK" || die "copy rgd_blank.png failed"
    chmod 644 "$ATLAS" "$BLANK"
    say "ok: $ATLAS"
    # A fully transparent bitmap. The HMI creates the overlay displayable from
    # it before the renderer has drawn anything; with no readable bitmap there
    # the displayable does not exist and the cluster overlay never appears.
    say "ok: $BLANK"

    # Compiled shaders. This firmware ships no GLSL compiler at all - the GL
    # driver looks for a plugin that is not in the image - so the renderer loads
    # its shaders as platform binaries instead of compiling them. Without these
    # it cannot draw.
    [ -d "$SHADER_DIR" ] || mkdir -p "$SHADER_DIR" || die "could not create $SHADER_DIR"
    for s in $SHADERS; do
        cp "$BIN_DIR/shaders/$s.bin" "$SHADER_DIR/$s.bin" || die "copy $s.bin failed"
    done
    chmod 644 "$SHADER_DIR"/*.bin 2>/dev/null
    say "ok: $SHADER_DIR"

    # The supervisor keeps exactly one renderer alive. Started by the shim
    # below, so it comes up with the CarPlay session and goes with the ignition.
    cat > "$SUPERVISOR.new" <<'SUP'
#!/bin/sh
# Keeps exactly one maneuver_render alive. Started in the background by the
# mm-ipod shim; exits when /mnt/app/rgd_disable appears.
BIN=/mnt/app/eso/hmi/lib/maneuver_render
LOG=/dev/null
# The lock lives in RAM on purpose: a reboot must clear it, and a stale lock
# from a hard power-off must not block the next start.
LOCK=/dev/shmem/rgd_render_sup.pid
# Two directories have to be searchable. /eso/lib holds libdisplayinit.so,
# which the renderer dlopens to create its window; the lib directory is its
# own, and being in it also lets it find flag_atlas.rgba and shaders/ by
# relative path.
LD_LIBRARY_PATH=/mnt/app/eso/hmi/lib:/eso/lib:$LD_LIBRARY_PATH
export LD_LIBRARY_PATH
cd /mnt/app/eso/hmi/lib 2>/dev/null

[ -f /mnt/app/rgd_disable ] && exit 0

if [ -f "$LOCK" ]; then
    read old < "$LOCK"
    # kill -0 only probes, it does not signal. A live pid means a supervisor is
    # already running and this invocation has nothing to do.
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then exit 0; fi
fi
echo $$ > "$LOCK"

# The CarPlay map in the cluster rides the same start: its own script decides
# whether to run (it is installed and switched on) and keeps itself single.
[ -x /mnt/app/eso/hmi/lib/altscreen_sup.sh ] && /mnt/app/eso/hmi/lib/altscreen_sup.sh &

while [ ! -f /mnt/app/rgd_disable ]; do
    "$BIN" >> "$LOG" 2>&1
    # A crash loop must not spin on flash writes.
    sleep 2
done
rm -f "$LOCK"
SUP
    chmod 755 "$SUPERVISOR.new"
    mv "$SUPERVISOR.new" "$SUPERVISOR" || die "could not install $SUPERVISOR"
    say "ok: $SUPERVISOR"

    # Upgrade from a release that drew maneuvers from pre-drawn pictures: about
    # 90 MB of PNGs in three sets, which nothing reads any more. Explicit paths
    # and explicit file names, never "rm -rf $VAR" - one empty variable there
    # would take the whole lib directory with it.
    if [ -d "$FRAMES_DIR" ]; then
        say "removing the old maneuver frames (~90 MB, no longer used)..."
        for stage in small large large_sport; do
            [ -d "$FRAMES_DIR/$stage" ] || continue
            rm -f "$FRAMES_DIR/$stage"/*.png "$FRAMES_DIR/$stage"/frames.idx 2>/dev/null
            # The unit has no rmdir, and its rm needs -r for a directory.
            rm -r "$FRAMES_DIR/$stage" 2>/dev/null
        done
        rm -r "$FRAMES_DIR" 2>/dev/null
        if [ -d "$FRAMES_DIR" ]; then
            say "note: $FRAMES_DIR is still there - its files are gone, the empty directory is harmless"
        else
            say "ok: removed $FRAMES_DIR"
        fi
    fi

    # The layout is normally read from the head unit itself (the cluster's
    # menu reaches it as a skin).  The marker forces the sport layout on a unit
    # where that does not follow; it can be changed any time without a reboot
    # (picked up within 5 s), and removing it hands control back.
    if [ "$SPORT" = "1" ]; then
        touch /mnt/app/rgd_sport || die "could not create /mnt/app/rgd_sport"
        say "ok: sport cluster layout selected (/mnt/app/rgd_sport)"
    elif [ "$SPORT" = "0" ]; then
        rm -f /mnt/app/rgd_sport
        say "ok: classic cluster layout selected"
    elif [ -f /mnt/app/rgd_sport ]; then
        say "keeping the sport cluster layout (/mnt/app/rgd_sport is present)"
    fi

    if [ "$ETA_DEFAULT" = "1" ]; then
        touch /mnt/app/rgd_eta_default || die "could not create /mnt/app/rgd_eta_default"
        say "ok: the line under the maneuver starts on the arrival time (/mnt/app/rgd_eta_default)"
    elif [ "$ETA_DEFAULT" = "0" ]; then
        rm -f /mnt/app/rgd_eta_default
        say "ok: the line under the maneuver starts on the next street"
    elif [ -f /mnt/app/rgd_eta_default ]; then
        say "keeping the arrival time first (/mnt/app/rgd_eta_default is present)"
    fi

    if [ "$MAP_ONLY" = "1" ]; then
        touch /mnt/app/rgd_map_only || die "could not create /mnt/app/rgd_map_only"
        say "ok: cluster map only, route guidance stays on the phone (/mnt/app/rgd_map_only)"
    elif [ "$MAP_ONLY" = "0" ]; then
        rm -f /mnt/app/rgd_map_only
        say "ok: route guidance in the cluster"
    elif [ -f /mnt/app/rgd_map_only ]; then
        say "keeping the cluster map without route guidance (/mnt/app/rgd_map_only is present)"
    fi

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
# The cluster renderer is a process of its own, and this shim is the one thing
# that already runs exactly when a CarPlay session starts.  Its supervisor is a
# singleton, so the replug that restarts mm-ipod does not stack copies.
[ -f /mnt/app/rgd_disable ] || [ ! -x /mnt/app/eso/hmi/lib/rgd_render_sup.sh ] || \
    /mnt/app/eso/hmi/lib/rgd_render_sup.sh &
exec /mnt/app/armle/usr/sbin/rgd_real/mm-ipod "$@"
SHIM
    chmod 755 "$SBIN/mm-ipod.new"
    mv "$SBIN/mm-ipod.new" "$SBIN/mm-ipod" || die "could not install the shim"
    say "ok: $SBIN/mm-ipod (shim)"
fi

# ---------------------------------------------------------------- altscreen
if [ "$ALTSCREEN" != "0" ]; then
    say ""
    say "--- CarPlay map in the cluster ---"
    cp "$BIN_DIR/altscreen_render" "$ALT_RENDER.new" || die "copy altscreen_render failed"
    chmod 755 "$ALT_RENDER.new"
    mv "$ALT_RENDER.new" "$ALT_RENDER" || die "could not put altscreen_render in place"
    say "ok: $ALT_RENDER"

    cp "$BIN_DIR/altscreen_sup.sh" "$ALT_SUP.new" || die "copy altscreen_sup.sh failed"
    chmod 755 "$ALT_SUP.new"
    mv "$ALT_SUP.new" "$ALT_SUP" || die "could not put altscreen_sup.sh in place"
    say "ok: $ALT_SUP"

    [ -d "$ALT_SHADER_DIR" ] || mkdir -p "$ALT_SHADER_DIR" || die "could not create $ALT_SHADER_DIR"
    for s in $ALT_SHADERS; do
        cp "$BIN_DIR/altscreen_shaders/$s.bin" "$ALT_SHADER_DIR/$s.bin" || die "copy $s.bin failed"
    done
    chmod 644 "$ALT_SHADER_DIR"/*.bin 2>/dev/null
    say "ok: $ALT_SHADER_DIR"

    touch "$ALT_ON" || die "could not create $ALT_ON"
    say "ok: switched on"
    if [ "$WIRELESS_MAP" = "1" ]; then
        touch "$ALT_FORCE" || die "could not create $ALT_FORCE"
        say "ok: offered to wireless adapters too (WIRELESS_MAP)"
    else
        rm -f "$ALT_FORCE"
    fi
else
    # Left out on purpose (ALTSCREEN=0, or RGI=0 which it rides on): take away
    # whatever an earlier install put there, so nothing of it keeps running.
    if [ -f "$ALT_ON" ] || [ -f "$ALT_RENDER" ] || [ -d "$ALT_SHADER_DIR" ]; then
        say ""
        say "--- CarPlay map in the cluster: removing an earlier install ---"
        rm -f "$ALT_ON" "$ALT_SUP" "$ALT_RENDER" "$ALT_FORCE" /mnt/app/altscreen_cluster_off
        if [ -d "$ALT_SHADER_DIR" ]; then
            rm -f "$ALT_SHADER_DIR"/*.bin 2>/dev/null
            rm -r "$ALT_SHADER_DIR" 2>/dev/null
        fi
        say "ok: removed"
    fi
fi

# ---------------------------------------------------------------- RGI=0
# Route guidance left out of an install that had it: undo it the way
# uninstall.sh does - the shim first, so that mm-ipod starts stock even if
# anything after it fails - instead of leaving the old version running beside
# the new jars.
if [ "$RGI" = "0" ] && { [ -f "$RGD_JAR" ] || [ -f "$SBIN/rgd_real/mm-ipod" ]; }; then
    say ""
    say "--- route guidance: removing an earlier install (RGI=0) ---"
    # Beside it and then over it: a running mm-ipod keeps the file busy, and
    # writing into it fails with "cannot create".
    if [ -f "$SBIN/mm-ipod.orig" ]; then
        cp "$SBIN/mm-ipod.orig" "$SBIN/mm-ipod.new" && chmod 755 "$SBIN/mm-ipod.new" \
            && mv "$SBIN/mm-ipod.new" "$SBIN/mm-ipod" \
            && say "restored $SBIN/mm-ipod" || die "could not restore $SBIN/mm-ipod"
    elif [ -f "$SBIN/rgd_real/mm-ipod" ]; then
        cp "$SBIN/rgd_real/mm-ipod" "$SBIN/mm-ipod.new" && chmod 755 "$SBIN/mm-ipod.new" \
            && mv "$SBIN/mm-ipod.new" "$SBIN/mm-ipod" \
            && say "restored $SBIN/mm-ipod" || die "could not restore $SBIN/mm-ipod"
    fi
    for f in "$SUPERVISOR" "$RENDER" "$ATLAS" "$BLANK" "$RGD_JAR" "$RGD_SO"; do
        [ -f "$f" ] && { rm -f "$f" && say "removed: $f" || say "!! could not remove $f"; }
    done
    if [ -d "$SHADER_DIR" ]; then
        rm -f "$SHADER_DIR"/*.bin 2>/dev/null
        rm -r "$SHADER_DIR" 2>/dev/null
        say "removed: $SHADER_DIR"
    fi
fi

# Files earlier releases read or wrote and this one does not.
rm -f /mnt/app/carplay_verbose /mnt/app/carplay_log_persist \
      /mnt/app/rgd_hook.log /mnt/app/rgd_hook.log.prev /mnt/app/rgd_render.log 2>/dev/null

# ---------------------------------------------------------------- done
say ""
say "--- installed files ---"
ls -l "$JARS_DIR/dpad_hook.jar" "$JARS_DIR/coverart_hook.jar" "$SO_DEST" 2>&1 | while IFS= read -r l; do say "$l"; done
[ "$PDC" = "1" ] && ls -l "$JARS_DIR/pdc_hook.jar" 2>&1 | while IFS= read -r l; do say "$l"; done
if [ "$RGI" != "0" ]; then
    ls -l "$RGD_JAR" "$RGD_SO" "$RENDER" "$ATLAS" "$BLANK" "$SUPERVISOR" "$SBIN/mm-ipod" 2>&1 \
        | while IFS= read -r l; do say "$l"; done
    ls -l "$SHADER_DIR" 2>&1 | while IFS= read -r l; do say "$l"; done
fi
if [ "$ALTSCREEN" != "0" ]; then
    ls -l "$ALT_RENDER" "$ALT_SUP" "$ALT_SHADER_DIR" 2>&1 | while IFS= read -r l; do say "$l"; done
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
say "After the reboot, plug in an iPhone by cable."
if [ "$RGI" != "0" ]; then
    say ""
    say "Route guidance is installed and on.  Start a route in Apple Maps or"
    say "Google Maps on the phone and the maneuver appears in the cluster."
    say "To turn it off later, without uninstalling anything:"
    say "  touch /mnt/app/rgd_disable   (then reboot)"
    say "force the sport cluster layout / back to automatic, no reboot needed:"
    say "  touch /mnt/app/rgd_sport  /  rm /mnt/app/rgd_sport"
    say "and to turn it back on, delete that file and reboot."
fi
if [ "$ALTSCREEN" != "0" ]; then
    say ""
    say "The CarPlay map is in the cluster in place of the stock one.  A long"
    say "press of the left steering-wheel roller swaps it for the stock map and"
    say "back; the choice is kept."
fi
say ""
say "This log: $LOG"
