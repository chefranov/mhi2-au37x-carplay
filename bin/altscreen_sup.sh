#!/bin/sh
# Keeps one altscreen_render --listen alive while the CarPlay map in the
# cluster is switched on (/mnt/app/altscreen_inject).  Started in the
# background by rgd_render_sup.sh, i.e. with the iAP2 session.  POSIX sh only:
# the unit has no awk, sed or pgrep on PATH.
BIN=/mnt/app/eso/hmi/lib/altscreen_render
LOG=/dev/null
LOCK=/dev/shmem/altscreen_sup.pid
FLAG=/dev/shmem/altscreen_live
MARKER=/mnt/app/altscreen_inject
# libdisplayinit and the GL driver's libcgdrv, as for maneuver_render; at the
# end what the hardware decoder (NvSS) loads besides:
# libnvparser and libnvmedia.
LD_LIBRARY_PATH=/eso/lib:/mnt/app/eso/hmi/lib:/lib:/usr/lib:$LD_LIBRARY_PATH:/mnt/app/root/lib-target:/mnt/app/armle/lib:/mnt/app/armle/usr/lib
export LD_LIBRARY_PATH

[ -f "$MARKER" ] || exit 0
[ -x "$BIN" ] || exit 0

if [ -f "$LOCK" ]; then
    read old < "$LOCK"
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then exit 0; fi
fi
echo $$ > "$LOCK"

# /mnt/app is read-only after every boot, and then the steering-wheel on/off
# choice cannot be saved.  Open it for the session; mount -uw on an already
# writable mount is harmless.
mount -uw /mnt/app 2>/dev/null

quick=0
while [ -f "$MARKER" ]; do
    "$BIN" --listen >> "$LOG" 2>&1
    rc=$?
    # A dead renderer must not leave the cluster on a context whose map
    # window is gone.
    rm -f "$FLAG"
    # 0 is a planned restart - one hardware decoder per process, so every new
    # sender or picture size takes a fresh one - and the hook is already
    # reconnecting: two seconds here were two seconds of the stock map.  A
    # crash still waits.
    # A renderer that exits 0 straight away, over and over, would spin a core:
    # there is no clock here to time an exit with, so every twentieth planned
    # restart in a row waits as well.
    if [ "$rc" -eq 0 ]; then
        quick=$((quick + 1))
        [ "$quick" -lt 20 ] || { quick=0; sleep 2; }
    else
        quick=0
        sleep 2
    fi
done
rm -f "$LOCK"
