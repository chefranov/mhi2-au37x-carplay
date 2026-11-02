#!/bin/sh
#
# custom.sh - M.I.B. entry point.
#
# Copy this file to /mod/custom.sh on the M.I.B. SD card and the rest of this
# repository to /mod/carplay/, then on the unit:
#
#     Advanced Settings -> Run Custom Script
#
# M.I.B. V3.6 and later name it "Run individual script" and run
# /mod/command.sh instead; that file only calls this one.
#
# It finds the payload on the card and runs install.sh. To uninstall instead,
# create an empty file named UNINSTALL next to install.sh on the card
# (/mod/carplay/UNINSTALL) and run the custom script again.
#
# To force route guidance onto the sport cluster layout (normally detected by
# itself), put an empty file named SPORT next to install.sh - see README,
# "The sport cluster layout".
# To install everything except route guidance, put an empty file named NO_RGI
# on the card beside install.sh; to leave out only the CarPlay map in the
# cluster, one named NO_ALTSCREEN.  An empty WIRELESS_MAP file offers the
# cluster map to a wireless adapter that does not ask for it (see the wiki,
# Compatibility).  An empty PDC file installs the parking popup beside CarPlay
# (P5089 and Q2 P5088 only).  If the installer stops on jars it does not
# know and you are sure they are harmless, an empty IGNORE_CONFLICTS file lets
# it go on.  There is no way to pass an environment variable through the
# M.I.B. menu, and the files combine.

set -u

echo "=== MHI2 AU37x CarPlay patches - M.I.B. launcher ==="

# The card can be mounted under different names depending on the reader, so
# look for our payload rather than assuming a path.
# `dirname` is missing too, so $0's directory is derived with ${0%/*} - which
# leaves $0 alone when there is no slash in it, hence the explicit "." case.
case $0 in
    */*) SELF_DIR=${0%/*} ;;
    *)   SELF_DIR=. ;;
esac

# Globs, not `find`: this unit has no find at all (/bin holds 40 utilities and
# that is not one of them), so a find-based search would fail silently and the
# script would report "payload not found" for the wrong reason. The shell
# expands these itself, and an unmatched pattern simply stays literal - the
# -f tests below reject it.
PAYLOAD=""
for d in \
    "$SELF_DIR/carplay" \
    /fs/*/mod/carplay \
    /mnt/*/mod/carplay \
    /net/*/fs/*/mod/carplay
do
    if [ -f "$d/install.sh" ] && [ -f "$d/bin/libcarplay_hook.so" ]; then
        PAYLOAD=$d
        break
    fi
done

if [ -z "$PAYLOAD" ]; then
    echo "!! payload not found."
    echo "!! Expected /mod/carplay/install.sh and /mod/carplay/bin/ on the card,"
    echo "!! with custom.sh itself at /mod/custom.sh."
    echo "!! Looked under: $SELF_DIR/carplay, /fs/*/mod, /mnt/*/mod, /net/*/fs/*/mod"
    exit 1
fi

echo "payload: $PAYLOAD"

if [ -f "$PAYLOAD/UNINSTALL" ]; then
    echo "UNINSTALL marker present - removing the patches"
    SRC_DIR="$PAYLOAD" sh "$PAYLOAD/uninstall.sh"
else
    R=1
    S=
    A=1
    if [ -f "$PAYLOAD/NO_RGI" ]; then
        echo "NO_RGI marker present - installing without route guidance"
        R=0
    fi
    if [ -f "$PAYLOAD/SPORT" ]; then
        echo "SPORT marker present - forcing the sport cluster layout for route guidance"
        S=1
    fi
    if [ -f "$PAYLOAD/NO_ALTSCREEN" ]; then
        echo "NO_ALTSCREEN marker present - installing without the CarPlay map in the cluster"
        A=0
    fi
    E=
    if [ -f "$PAYLOAD/ETA_DEFAULT" ]; then
        echo "ETA_DEFAULT marker present - the line under the maneuver starts on the arrival time"
        E=1
    fi
    M=
    if [ -f "$PAYLOAD/MAP_ONLY" ]; then
        echo "MAP_ONLY marker present - the cluster map without route guidance"
        M=1
    fi
    W=0
    if [ -f "$PAYLOAD/WIRELESS_MAP" ]; then
        echo "WIRELESS_MAP marker present - offering the cluster map to wireless adapters"
        W=1
    fi
    P=0
    if [ -f "$PAYLOAD/PDC" ]; then
        echo "PDC marker present - installing the parking popup beside CarPlay (P5089 / Q2 P5088 only)"
        P=1
    fi
    I=0
    if [ -f "$PAYLOAD/IGNORE_CONFLICTS" ]; then
        echo "IGNORE_CONFLICTS marker present - unknown jars will not stop the install"
        I=1
    fi
    SRC_DIR="$PAYLOAD" RGI=$R SPORT=$S ETA_DEFAULT=$E MAP_ONLY=$M ALTSCREEN=$A WIRELESS_MAP=$W PDC=$P IGNORE_CONFLICTS=$I \
        sh "$PAYLOAD/install.sh"
fi

echo ""
echo "Read the log above, then reboot the unit."
