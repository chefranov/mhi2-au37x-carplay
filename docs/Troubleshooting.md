# Verifying and troubleshooting

Back to the [README](../README.md).

## Verify

Both the native hook and the HMI patch log to the same file on the unit. Plug in an
iPhone, play something with artwork, then:

```sh
cat /tmp/carplay_hook.log
```

A healthy cover-art run looks like this:

```
[INF] new artwork id=130 size=53964
[INF] artwork decoded 600x600 (3 ch) -> 170x170
[INF] published coverart: crc=b5012bdf size=53964
[CarplayBus] hook connected from /127.0.0.1
[CoverArt] New cover art: crc=b5012bdf
[CoverArtProvider] requestPicture entryID=0 sourceType=0 known=true
```

That last line is the cluster asking for the picture — if it never appears, check the
module 17 adaptation. The installer's own log is at `/tmp/carplay_install.log`.

## Troubleshooting

**`./install.sh: No such file or directory` — but the file is right there and
executable.** Also `: unknown optionset: -` and `install.sh[21]: set:`. The scripts have
Windows line endings. `#!/bin/sh` became `#!/bin/sh\r`, so the shell looks for an
interpreter that does not exist, and `set -u\r` is not a valid command either.

Git on Windows converts to CRLF on checkout by default. This repository now pins LF for
`*.sh` in `.gitattributes`, so **re-download it** (clone again, or Code → Download ZIP)
and the copies will be correct. If you would rather fix the working copy you already
have: `git config --global core.autocrlf input`, then delete the clone and clone again.

If a broken copy is already on the unit, the only tool there that can repair it is `vi` —
there is no `sed`, no `awk`, no `tr` and no `printf`. See
[the vi recipe](Installation.md#before-you-copy-anything-windows-line-endings).

**The M.I.B. custom script does nothing.** Same cause in most cases — a CRLF `custom.sh`
dies before it prints anything. Otherwise check the layout on the card: the file M.I.B.
runs is exactly `/mod/custom.sh`, and the payload must be at `/mod/carplay/` next to it,
not inside it.

**`mkdir: <name>: Function not implemented`.** You are somewhere under `/tmp`, which is
`/dev/shmem` and holds no directories. Use a path on `/mnt/app` instead.

**`Read-only filesystem`.** `mount -uw /mnt/app` and `mount -uw /mnt/system` — the
installer does this itself, but a manual `cp` beforehand needs it too.

**The installer said `LD_PRELOAD already present` on a unit you never patched.** That was
a bug, fixed on 2026-08-31. Stock already carries an unrelated
`LD_PRELOAD=/eso/lib/libsystemtime_hack.so` on a different child, and the installer's
idempotency check looked for `LD_PRELOAD` anywhere in the file — so it always decided the
work was done and never added ours. The jars still installed (the D-pad patch was
unaffected), but the hook was never preloaded and cover art could not work. Re-run the
current `install.sh`; it now looks for `libcarplay_hook.so` specifically. To check by
hand:

```sh
grep libcarplay_hook.so /mnt/system/etc/eso/production/smartphone_integrator.json
```

One match means you are set.

**Cover art comes up torn — solid green or magenta bands across it — when skipping
tracks quickly.** The picture travels to the cluster over BAP, which is slow; a burst of
skips used to start one transfer per skip, so a new one began before the previous had
finished and the cluster painted a buffer written by two different pictures. This is not
a compression artifact: the file is a PNG and PNG is lossless, so it either decodes
correctly or not at all.

Two changes address it, both in the 2026-09-01 build:

* The artwork is now scaled to **170×170** instead of 256×256 — 0.44× the bytes on the
  bus, so the transfer window is less than half as wide. The picture server rescales to
  the cluster's own resolution anyway, so nothing looks smaller.
* While skips are still arriving, only the track text is sent; the picture is held back
  and pushed once the track has stayed put for about a second and a half.

If you still see bands after updating, first confirm you are actually on the new build —
`ls -l /mnt/app/eso/hmi/lib/libcarplay_hook.so` should read **124703** — and then send
the tail of `/tmp/carplay_hook.log` covering the skips.

**You plug the phone in while music is already playing and there is no cover until you
skip a track.** Fixed in the 2026-09-03 build. The cluster push is dropped while
CarPlay is not the active audio source, and that can last as long as the driver takes to
select it. The retry ran once a second and gave up after ten attempts, so a cover that
only needed waiting for was abandoned, and only the next track change brought it back.
The push is now held — silently, without hammering the bus — until audio focus arrives,
and sent the moment it does. In the log:

```
[TMEventListener] cover held until audio focus arrives (cover push not delivered)
[DIAG] audio focus -> true
[TMEventListener] audio focus gained - sending the cover that was held back
```

**The first cover of a CarPlay session is missing, and appears once you change track.**
Fixed in the 2026-09-03 build. The Java half dedupes artwork by checksum so the same
picture is not pushed to the cluster twice, and it lives inside the HMI, which is not
restarted between sessions — so it had no idea a new session had started. Plug the phone
back in on the same track, the identical artwork arrives, and it was discarded as a
repeat. The hook now announces a new session and the Java half clears what it remembered.

In the log:

```
[INF] CarPlay session started - HELLO sent
```

and on the Java side `State reset (prevCrc=...)`.

## Recovery

If the HMI does not come up after a reboot, **telnet on port 23 still works** and does not
depend on the HMI or on sshd. Get in and delete the jars:

```sh
rm /mnt/app/eso/hmi/lsd/jars/coverart_hook.jar
rm /mnt/app/eso/hmi/lsd/jars/dpad_hook.jar
```

then reboot. That alone returns the HMI to stock; the native hook and the config entry are
harmless without the jars, and `uninstall.sh` cleans them up afterwards.
