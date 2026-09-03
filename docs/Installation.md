# Installation

Back to the [README](../README.md). Check [Compatibility](Compatibility.md) first, and
read [Recovery](Troubleshooting.md#recovery) before you start.

## Before you copy anything: Windows line endings

If you are on Windows, **download this repository fresh** (clone again, or Code →
Download ZIP). Earlier copies were checked out with CRLF line endings and every script in
them fails on the unit; `.gitattributes` now pins LF, but it only affects new downloads.

You have a CRLF copy if the unit answers like this:

```
: cannot execute - No such file or directory
: unknown option
install.sh[21]: set:
```

Repairing it **on the unit** is harder than it sounds, because the unit is missing most of
the tools you would reach for. This is the complete inventory:

```
/bin      cat chgrp chkqnx6fs chmod chown cp dd df dinit echo fdisk flashctl getconf
          head hogs if_up ksh link ln login ls mkdir mkqnx6fs mount mv on pidin rm
          setconf sh slay sleep sloginfo swaitfor sync sysctl tail touch umount uname
          usb use vi waitfor waitforpoll
/usr/bin  cut fsmounter grep sort tee
```

No `sed`, no `awk`, no `tr`, no `printf`. What does work is `vi`:

```sh
vi install.sh
```

Type `:%s/` then **Ctrl-V Ctrl-M** (this inserts a literal carriage return, shown as `^M`)
then `//g` and Enter, so the command line reads `:%s/^M//g`. Then `:wq`. Repeat for
`uninstall.sh`. If vi reports *No match*, the file was already fine and the problem is
elsewhere.

Honestly though: fixing the line endings on your own machine before copying is less work
than any of this, and the [manual install](#manual-install--no-scripts) below needs no
scripts at all.

After any download, check the payload arrived intact — these are exact sizes:

```
bin/libcarplay_hook.so   124703
bin/coverart_hook.jar     27848
bin/dpad_hook.jar         11108
```

Or skip the scripts entirely: see [Manual install](#manual-install--no-scripts).

## Install A — network cable

Prerequisites, both from the M.I.B. menu:

1. `Advanced Settings → Info USB Ethernet devices → Install devices (again)`
2. `Advanced Settings → Install SSHD` (put your `id_rsa.pub` in the card's `Custom`
   folder first)

Plug the USB-Ethernet adapter in; the unit comes up on **`172.16.250.248`**.

```sh
# from your machine, in this repository
ssh root@172.16.250.248 'mount -uw /mnt/app; mkdir -p /mnt/app/root/carplay'
scp -O -r bin install.sh uninstall.sh root@172.16.250.248:/mnt/app/root/carplay/
ssh root@172.16.250.248 'sh /mnt/app/root/carplay/install.sh'
```

**Do not stage the files under `/tmp`.** On this unit `/tmp` is a symlink to
`/dev/shmem`, a flat shared-memory filesystem that has no directories at all —
`mkdir /tmp/carplay` fails with *Function not implemented*. Any writable spot on
`/mnt/app` works; the line above uses `/mnt/app/root/carplay`.

(`-O` is needed on recent macOS/OpenSSH, which defaults to SFTP; the unit only speaks the
legacy SCP protocol. Older systems: drop it. If the unit's host key is rejected, add
`-o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa`.)

Then reboot the unit.

## Install B — M.I.B. SD card

Lay the card out like this:

```
/mod/custom.sh            <- copy of custom.sh from this repository
/mod/carplay/install.sh
/mod/carplay/uninstall.sh
/mod/carplay/bin/coverart_hook.jar
/mod/carplay/bin/dpad_hook.jar
/mod/carplay/bin/libcarplay_hook.so
```

Insert the card and run `Advanced Settings → Run Custom Script`. It locates the payload,
installs, and prints what it did.

Then reboot the unit.

To uninstall this way, create an empty file `/mod/carplay/UNINSTALL` on the card and run
the custom script again.

> Give the writes a moment before rebooting — the installer calls `sync` and waits, but a
> forced reboot immediately afterwards can still leave a file truncated, and you will be
> left wondering why nothing loaded.

## Manual install — no scripts

Nine commands on the unit. Do this if the scripts give you trouble, or if you would rather
see every change go by.

```sh
mount -uw /mnt/app
mount -uw /mnt/system

# 1. the jars
cp bin/dpad_hook.jar     /mnt/app/eso/hmi/lsd/jars/
cp bin/coverart_hook.jar /mnt/app/eso/hmi/lsd/jars/

# 2. the native hook
mkdir -p /mnt/app/eso/hmi/lib
cp bin/libcarplay_hook.so /mnt/app/eso/hmi/lib/

# 3. make all three readable (a jar lsd cannot read is skipped silently)
chmod 755 /mnt/app/eso/hmi/lsd/jars/dpad_hook.jar \
          /mnt/app/eso/hmi/lsd/jars/coverart_hook.jar \
          /mnt/app/eso/hmi/lib/libcarplay_hook.so

# 4. back up the one config you are about to edit
cp /mnt/system/etc/eso/production/smartphone_integrator.json \
   /mnt/system/etc/eso/production/smartphone_integrator.json.orig
```

Then edit the config — `vi` is on the unit:

```sh
vi /mnt/system/etc/eso/production/smartphone_integrator.json
```

Search for `IPL_CONFIG_DIR_DIO_MANAGER` (`/IPL_CONFIG_DIR_DIO_MANAGER` then Enter). It
appears exactly once, on the `carplay` child's `envs` line. Add one entry at the end of
that array, so the line ends like this:

```
… "IPL_CONFIG_DIR_DIO_MANAGER=/etc/eso/production", "LD_PRELOAD=/mnt/app/eso/hmi/lib/libcarplay_hook.so"],
```

Save and quit (`:wq`), then `sync`, wait a few seconds, and reboot.

**Only want the touchpad D-pad?** Step 1's first line plus its `chmod` is the whole
install — no hook, no config edit.

## What the installer changes

| Path | Change | Backup |
|---|---|---|
| `/mnt/app/eso/hmi/lsd/jars/coverart_hook.jar` | new file | — (delete to undo) |
| `/mnt/app/eso/hmi/lsd/jars/dpad_hook.jar` | new file | — (delete to undo) |
| `/mnt/app/eso/hmi/lib/libcarplay_hook.so` | new file | — (delete to undo) |
| `/mnt/system/etc/eso/production/smartphone_integrator.json` | one `LD_PRELOAD` entry added to the `carplay` child's `envs` | `…json.orig`, written once |

Nothing stock is overwritten, so only that one config needs a backup. The edit is
line-based on purpose: the file is JSON with `#` metadata and `##` comment lines that any
JSON rewriter would silently drop, and it is written *through* the existing file rather
than replacing it, so the config keeps its own mode and owner.

**Permissions.** The installer `chmod 755`s everything it copies. This matters on the SD
card path: FAT32 carries no Unix modes, so a jar can land unreadable, and `lsd` skips a
jar it cannot read without logging anything — you would see no patch and no error. Stock
files in that directory are `-rwxrwxrwx root:root`. The installer prints an `ls -l` of the
three files at the end so you can check. Nothing on the card needs the executable bit:
`custom.sh` is invoked as `sh custom.sh`, and it calls the other scripts the same way.

The jars need no loader change — `lsd.sh` already scans
`/mnt/app/eso/hmi/lsd/jars/` and puts what it finds on the bootclasspath *ahead* of
`lsd.jxe`, which is what lets a patched class win over the stock one.

## Upgrading

Just run `install.sh` again — there is no need to uninstall first. It overwrites the
files, keeps the `.orig` backup it already made, and leaves the config alone once our
`LD_PRELOAD` entry is there. The hook is put in place with `rename`, so an upgrade does
not disturb a `dio_manager` that happens to be running; the new one takes effect at the
next start.

Reboot afterwards, as with a first install.

## Uninstall

```sh
ssh root@172.16.250.248 'sh /mnt/app/root/carplay/uninstall.sh'
```

or the `UNINSTALL` marker file described above. Reboot afterwards. The `.orig` backup is
deliberately left behind; remove it by hand if you want no trace.
