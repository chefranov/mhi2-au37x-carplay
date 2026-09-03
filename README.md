# MHI2 AU37x CarPlay patches

Two patches for Audi MHI2 head units on the **`MHI2_ER_AU37x`** train:

- **Cover art** — CarPlay album artwork on the Virtual Cockpit's now-playing widget.
  Stock forwards title/artist/album to the cluster but never the picture.
- **Touchpad → D-pad** — the MMI touchpad navigates CarPlay menus. Stock bridges the
  rotary, the knob press, back and the softkeys, but leaves the touchpad dead.

Prebuilt binaries only. Two ways to install: straight over a network cable, or from an
M.I.B. SD card.

> **Use at your own risk.** These patches copy files onto the head unit's flash and edit
> one system config. Everything is reversible and the installer backs up the one file it
> changes, but a head unit is not a toy. Read
> [Recovery](docs/Troubleshooting.md#recovery) *before* you start, and make sure you can
> get a shell on the unit without the screen.

<p align="center"><img src="docs/coverart.jpg" width="80%" /></p>

<p align="center"><sub>CarPlay album art on the Virtual Cockpit — stock leaves this tile empty.</sub></p>

## Will it work on my car?

Tested on exactly one build: `MHI2_ER_AU37x_P5089`, `MU1326`, part `8V1035036A`, an Audi
A3 8V Sportback e-tron (2017) with the Virtual Cockpit and the HARMAN iAP2 stack.

Other `MHI2_ER_AU37x_*` builds are expected to work but are not verified. Two things
decide it, and one of them can keep the HMI from starting — **[read Compatibility before
installing](docs/Compatibility.md)**.

Two requirements worth knowing up front:

- **Cover art needs the cluster coded for it**: module **17**, adaptation
  `Picture_Upload_Download` set to **active**. Without it the cluster never asks for a
  picture and nothing on the head-unit side can help.
- **The D-pad patch needs no coding**, and is self-contained: copy `bin/dpad_hook.jar`
  into `/mnt/app/eso/hmi/lsd/jars/` and you are done. It is the lowest-risk way to try
  any of this.

## Contents

| Path | What it is |
|---|---|
| `bin/coverart_hook.jar` | HMI patch: pushes the artwork to the cluster and answers its picture requests |
| `bin/dpad_hook.jar` | HMI patch: touchpad drag → CarPlay D-pad |
| `bin/libcarplay_hook.so` | Native hook (ARM/QNX), `LD_PRELOAD`ed into `dio_manager`: pulls the artwork out of iAP2, decodes it, writes a 170×170 PNG |
| `install.sh` | Runs **on the unit**; does the whole install, idempotent |
| `uninstall.sh` | Runs on the unit; puts everything back |
| `custom.sh` | M.I.B. entry point — finds the payload on the card and calls the above |

Exact sizes, worth checking after any download:

```
bin/libcarplay_hook.so   124703
bin/coverart_hook.jar     27848
bin/dpad_hook.jar         11108
```

**On Windows, download this repository fresh** (clone again, or Code → Download ZIP).
Earlier copies were checked out with CRLF line endings and every script in them fails on
the unit. `.gitattributes` now pins LF, but only for new downloads — the
[repair recipe](docs/Installation.md#before-you-copy-anything-windows-line-endings) is
more work than re-downloading.

## Install

Over a network cable, with the USB-Ethernet adapter installed from the M.I.B. menu:

```sh
ssh root@172.16.250.248 'mount -uw /mnt/app; mkdir -p /mnt/app/root/carplay'
scp -O -r bin install.sh uninstall.sh root@172.16.250.248:/mnt/app/root/carplay/
ssh root@172.16.250.248 'sh /mnt/app/root/carplay/install.sh'
```

Then reboot. Do not stage the files under `/tmp` — it holds no directories on this unit.

From an M.I.B. SD card: put `custom.sh` at `/mod/custom.sh` and the rest of the
repository at `/mod/carplay/`, then run `Advanced Settings → Run Custom Script` and
reboot.

Full walkthrough of both, plus a scripts-free manual install and the list of everything
that gets changed: **[Installation](docs/Installation.md)**.

Upgrading is just running `install.sh` again — no need to uninstall first.

## Verify

Plug in an iPhone, play something with artwork, then read `/tmp/carplay_hook.log` on the
unit. A healthy run ends with the cluster asking for the picture:

```
[INF] artwork decoded 600x600 (3 ch) -> 170x170
[INF] published coverart: crc=b5012bdf
[CoverArtProvider] requestPicture entryID=0 sourceType=0 known=true
```

If that last line never appears, check the module 17 adaptation. What the other lines
mean, and what to do when they are missing:
**[Verifying and troubleshooting](docs/Troubleshooting.md)**.

## Uninstall

```sh
ssh root@172.16.250.248 'sh /mnt/app/root/carplay/uninstall.sh'
```

or create an empty `/mod/carplay/UNINSTALL` on the card and run the custom script again.
Reboot afterwards.

## Credits

Derived from [luka-dev/mib2q-carplay-rgi](https://github.com/luka-dev/mib2q-carplay-rgi) —
the HMI class-patch pattern and the cover-art pipeline come from there. That project
targets the Cinemo/Qualcomm MHI2Q stack; the native side here is a rewrite for the HARMAN
iAP2 stack these AU37x units use.

Thanks to [Mich795](https://github.com/Mich795), who took this build apart and sent back
a version of their own. Several fixes in the 2026-09-03 release came from reading it: the
session boundary that stops the first cover of a session being discarded as a duplicate,
dropping a fetch when the phone has already moved to another track, retrying a fetch whose
bytes have not arrived yet, and reusing artwork already built.

Route guidance (CarPlay maneuvers on the cluster) is being worked on and is not part of
this repository yet.
