# Compatibility

Back to the [README](../README.md).

**Tested on exactly one build:**

| Property | Value |
|---|---|
| Train | `MHI2_ER_AU37x_P5089` |
| MU | `MU1326` |
| Part number | `8V1035036A` |
| Car | Audi A3 8V Sportback e-tron (2017), Virtual Cockpit (`KI_FPK_AU37X`) |
| iAP2 stack | HARMAN (`mm-ipod` + `libiap2client.so.1`), Media 1.0.61.9 |

Other `MHI2_ER_AU37x_*` builds are **expected** to work but are **not verified**, and the
failure mode is worth understanding before you try:

- The jars do not add code alongside the stock HMI, they **replace three stock classes
  outright** (`AppConnectorTerminalMode`, `TerminalModeBapCombi$EventListener`,
  `CarplayDSILifecycleController$TerminalModeDSIKeyEventsController`). Each carries a copy
  of that class from the build above. If your build's version differs, the replacement can
  fail when the class loads — and since one of them is constructed during HMI audio-module
  init, that can mean the HMI does not come up, not just a dead feature.
- The native hook resolves `iap2_nowplay_getartwork` / `iap2_filexfer_read` out of
  `libiap2client.so.1` by name. A different driver version fails softly: a line in the log,
  no cover art, nothing broken.

Two checks on the unit before installing — **with an iPhone plugged in**:

```sh
pidin ar | grep mm-ipod          # HARMAN iAP2 stack running?
ls /ramdisk/pps/iap2/            # device, location, nowplaying, telephony
```

`mm-ipod` is started when a device is connected, and `/ramdisk/pps/iap2/` only exists
while it runs. With nothing plugged in, the first prints only your own `grep` and the
second says *No such file or directory* — that is normal and tells you nothing.

If there is no `mm-ipod` and `dio_manager` contains `NmeIAP2Message` symbols, you are on
the Cinemo/Qualcomm stack (MHI2Q) — these binaries are not for you; see
[mib2q-carplay-rgi](https://github.com/luka-dev/mib2q-carplay-rgi).

**Cover art additionally needs the cluster coded for it.** In module **17** (instrument
cluster), adaptation `Picture_Upload_Download` must be **active**. With it inactive the
cluster never asks for a picture and nothing on the head-unit side can help. The D-pad
patch needs no coding.

**Lowest-risk option:** the D-pad patch is self-contained. Copy only
`bin/dpad_hook.jar` into `/mnt/app/eso/hmi/lsd/jars/` — no native hook, no config edit,
uninstall is deleting the file.
