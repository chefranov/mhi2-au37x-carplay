# Changelog

Each release is on the [Releases](https://github.com/chefranov/mhi2-au37x-carplay/releases)
page, with a ready-made SD card archive.

## v1.1.12 — 2026-11-14

- **The maneuver arrow fills as you approach the turn.** It rests white and fills
  blue from its tail along with the progress bar, then flashes with the bar at the
  turn. Idea and colours from luka-dev's mib2q-carplay-rgi. To keep the plain arrow:
  `touch /mnt/app/rgd_no_arrow_fill` and reboot.
- **Lane guidance no longer stays up after the turn** when the next maneuver has no
  lanes. The cluster kept the passed turn's lanes until the route ended; they now go
  as soon as the phone stops showing them. Reported upstream by luka-dev.
- **The first maneuver shows up straight away** when CarPlay connects to a route that
  is already running, after switching navigation apps, and after a reroute. Apple
  Maps sends a route's maneuvers before the route itself, and those used to be
  dropped, so the tile stayed empty until the next turn.
- **A running route no longer ends by itself** when it resumes right after a short
  stop of guidance, and the distance of a turn you have just passed is no longer
  shown for the next one.
- **Roundabouts and ramps are drawn for left-hand traffic in right-hand-drive cars**
  (UK, Cyprus, …) when the navigation app doesn't say which side the traffic drives
  on. The app's own value still wins.
- **Sport layout:** the progress bar beside the maneuver starts lower, clear of the
  line the cluster draws across the top of the well.

## v1.1.11 — 2026-11-09

- **The installer refuses European AU37x builds up to `MHI2_ER_AU37x_P3242`** (#70).
  Their HMI is older than the classes the mod replaces: on P3242 the D-pad and route
  guidance don't match it, and installing would most likely keep the MMI from starting.
  The installer now stops before changing anything and asks for a firmware update.
  P3620 and newer, and CN and US builds, are not affected. No other changes.

## v1.1.10 — 2026-11-07

- **Black square in the cluster after switching back to the stock map is fixed**
  (#59, #64). Going back to the stock map, the mod restored the layout with the stock
  maneuver box even without a stock route; it now uses the plain map layout the unit
  itself would. Confirmed on `MHI2_CN_AU37x_P1003` and `MHI2_ER_AU37x_P3620`; the VIEW
  workaround is no longer needed.
- **Smoother maneuver animations** in the cluster tile: the renderer redraws less
  per frame (about 10 % faster frames, the heaviest ones most).
- **The maneuver comes back after a replug** when the phone resumes a route without
  resending its maneuver list; the tile used to stay dark for the rest of the session.

## v1.1.9 — 2026-11-02

- **Black square in the cluster after switching back to the stock map** (#13, #59,
  Chinese firmware): the maneuver tile's backing plates are now put in place before
  they are shown and are no longer raised by a switch to the stock map, and an unused
  overlay layer is down to one pixel. Not confirmed fixed yet; if it still shows, the
  VIEW button clears it.
- **The maneuver arrow appears at the start of every route**, also through a
  wireless adapter. The cluster can raise its tile without telling the head unit,
  and the arrow used to wait for the VIEW button. The stock map no longer flashes for
  a moment as a CarPlay route starts.
- **Off the road** (a route started in a car park) the empty tile keeps its plate
  instead of showing a hole with the map in it.
- **No black bar under the lane arrows in the Sport layout's small view**: the lanes sit
  on the cluster's own background there, and the maneuver ends above them.
- **The trip line drops its "ETA" prefix** (#51): `17:42 | 23 min | 18 km`.
- **`MAP_ONLY`**: the CarPlay map in the cluster without route guidance (#22, #38).
- **Parking sensors over CarPlay** (with `PDC`, #42): after the reverse camera,
  CarPlay comes back when the sensors stay on, without the "Look! Safe to move?"
  screen and without the head unit's menu bar; the sensor background is redrawn
  trimmed in that case too.
- **Uninstall** no longer reports "could not restore mm-ipod".

## v1.1.8 — 2026-10-23

- **The arrival-time line under the maneuver now shows the distance left too**
  (#45): `ETA 17:42 | 23 min | 18 km`, in miles where the head unit is set to miles.
  In the small/Sport layout the line is narrow and keeps one field.
- **The AUG22 test build is gone.** The project covers the A3 8V (AU37x) and the Q2
  (AU276) only; on AUG22 firmware the installer now stops like on any other
  unsupported train.

## v1.1.7 — 2026-10-22

- **The parking-sensors popup over CarPlay no longer has a crooked black strip
  under its frame** (with `PDC`). The stock background ends in a black band that
  normally merges with the head unit's bottom bar; over CarPlay that bar is hidden,
  so the band hung below the frame. A trimmed copy of the background is used only
  while the popup sits on CarPlay; without CarPlay the popup is unchanged.
- **The parking camera no longer switches the head unit to its main menu** behind
  it while CarPlay is on (part of #42). Getting back to CarPlay after reverse while
  the sensors stay on is still being worked on.

## v1.1.6 — 2026-10-22

- **The TEL key on the MMI console now opens CarPlay on every press** (#13). Before,
  a press while CarPlay was already on screen brought up the head unit's "Switch to
  Apple CarPlay" screen, and only the press after that went to CarPlay, so it worked
  every other time. The steering-wheel phone key and Phone in the main menu were not
  affected. A fast double press may flash that screen for a moment, then returns to
  CarPlay by itself.

## v1.1.5 — 2026-10-22

- **New install option `ETA_DEFAULT`**: the line under the maneuver starts on the
  arrival time with the time left instead of the next street (#39). An empty
  `ETA_DEFAULT` file on the card, or `ETA_DEFAULT=1 sh install.sh`. A short press of
  the left roller still swaps the two. A reinstall without it keeps the setting;
  uninstalling clears it.

## v1.1.4 — 2026-10-21

- **The maneuver in the cluster follows the cluster's own tile.** The head unit now
  listens to the cluster saying when it raises and drops the maneuver tile, and on
  which stage, instead of guessing with timers. The maneuver appears and goes together
  with the tile, with no window hanging in the air and no empty plate, and moves at
  once when View switches between the wide tile and the speedometer well.
- **Google Maps' maneuver card is back in the small stages** of the CarPlay map in
  the cluster, Sport and Classic. The area reserved for it was 20 px too short, and
  Google Maps drew the card empty.
- **A route in the head unit's own navigation while the CarPlay map is in the
  cluster** now switches the cluster to the stock map with its own maneuver tile, and
  back to the CarPlay map when that route ends. Before, the stock tile showed as a
  hole in the CarPlay map.
- **The CarPlay map in the cluster recovers by itself** from a lost or late frame: the
  head unit asks the phone for a fresh key frame instead of showing the stock map, and
  the cluster video is decoded at a higher priority. Behind a wireless adapter that does
  not take the cluster layout, the Sport well no longer shows the left edge of the
  large map (#38).
- **Day and night for the cluster map** are now sent to the cluster display as well
  as to the main screen, and a stale day/night value is no longer offered to the phone
  after a restart (#28). Still to be confirmed in daylight.
- **The head unit no longer treats CarPlay navigation as taking its own over**, the
  way M.I.B.'s NavActiveIgnore does, but for navigation only: calls and Siri are left
  alone. While a CarPlay route runs, a route set in the head unit's navigation waits
  until the CarPlay route ends. `touch /mnt/app/rgd_no_navignore` turns this off.
- **The parking popup beside CarPlay is now off by default** and installed only on
  request, `PDC=1` or an empty `PDC` file on the card, and still only on P5089 and Q2
  P5088. `PDC=1` no longer forces it onto other firmware: there it kept the HMI on the
  start logo. Reinstalling without `PDC=1` removes a copy an earlier release put there.

## v1.1.3 — 2026-10-18

- **CarPlay no longer drops over a wireless adapter.** After a minute of silence from the
  phone, for example after a route was cancelled, the hook asked for route guidance
  again. A wireless adapter never acknowledges that second request; the request was
  resent until the USB link gave out, and CarPlay went down a few minutes later. The
  repeat request came with v1.1.0 and is now off.
- **Calling a favourite from the cluster works** (#29). The iPhone sends favourites with
  the number as the contact spells it, `+48 600 123 456` or `(600) 123-456`, and iOS
  ignored that as a phone number. The number is now cleaned before dialling.
- **A short press of the left roller** swaps the line under the maneuver between the
  next street and the arrival time with the time left. `touch /mnt/app/rgd_eta_default`
  starts each route on the arrival time (#25).
- **The phone's cluster URL in `altscreen_url` stays** when the phone suggests another
  one (#25).
- No straight arrow off the road with Google Maps when the route starts with its
  "start" step and no distance.
- The finish flag goes away 30 s after the phone falls silent next to the destination,
  for when the phone's closing message is lost.
- `touch /mnt/app/rgd_no_tel` now turns the whole cluster phone tab back to stock, not
  only the iPhone lists.
- Under test for #28 (night map in the cluster in daylight), off by default:
  `touch /mnt/app/altscreen_night_resend` sends the day/night state to the phone again
  once the cluster map is up.

## v1.1.2 — 2026-10-17

- **The parking popup beside CarPlay is installed only on firmware it was checked
  against** (P5089, Q2 P5088). It replaces stock HMI classes, and on other firmware they
  differ: on CN P0916 v1.1.0 left the unit on the start logo (#27). Elsewhere the
  installer leaves it out and removes a copy an earlier release put there; `PDC=1`, or an
  empty `PDC` file on the card, installs it anyway.
- The cluster-map worker no longer spins while the cluster's display manager is still
  starting. It used about 10 % CPU for the first minute after every start (#26).

## v1.1.1 — 2026-10-17

- **The missed-call indicator in the cluster clears.** The Tel key on the steering wheel
  or opening the phone on the head unit clears it, as with a Bluetooth phone. Before, it
  stayed lit until the next answered or outgoing call. Calls missed before the phone was
  connected no longer light it: the iPhone already shows them.

## v1.1.0 — 2026-10-17

- **The cluster's phone tab works with CarPlay.** Instead of "Your iPhone is in Apple
  CarPlay mode" it shows calls as with a Bluetooth phone: caller and number, calling,
  ringing, in call with a timer, on hold. Accept, end, hold, swap, mute and dialling from
  recents and favourites work from the cluster, and it shows the phone's signal and
  carrier.
- **The Tel key goes straight to CarPlay**, with no "Switch to Apple CarPlay" popup, and
  so does Phone in the main menu.
- **Siri on a short press of the voice key.** A long press works as before; without
  CarPlay the short press starts the car's own voice control.
- **Parking sensors keep CarPlay on screen.** The side sensors open their popup beside
  CarPlay instead of the full parking screen. Reverse gear is unchanged.
- **No empty maneuver tile off the road.** With a route on the phone but the car off it,
  the cluster closes its maneuver tile instead of showing a straight arrow that pointed
  nowhere; it comes back with the first turn.
- **Lane guidance along the whole route**, not only at its start, with lane arrows drawn
  like the stock head-up display's.
- An empty `WIRELESS_MAP` file on the card offers the cluster map to wireless adapters
  that do not ask for it, such as the Carlinkit 2Air (#25). Off by default.
- The installer checks for another mod's `LD_PRELOAD` in `dio_manager` before changing
  anything. Before, it found it only after the jars were already copied.

## v1.0.0 — 2026-10-15

The first numbered release. It contains everything below, plus:

- **The installer checks for other mods before changing anything.** It stops if MIBSI,
  mib2q-carplay-rgi or another wrapper around `mm-ipod` is installed, if `lsd.sh` puts other
  code on the HMI classpath, or if there are jars it does not recognise in
  `/mnt/app/eso/hmi/lsd/jars/`. Two mods that replace the same HMI classes can leave the
  main screen black. If you know the unknown jars are harmless, install with
  `IGNORE_CONFLICTS=1`, or put an empty `IGNORE_CONFLICTS` file on the card.
- **M.I.B.'s NavActiveIgnore is switched off.** It makes every CarPlay app state read 0,
  so the HMI loses track of what CarPlay owns. The installer renames the jar to
  `*.carplay-off`, and uninstalling renames it back.
- **SD card archives.** Copy the `mod` folder from the archive to the root of the card and
  run the M.I.B. script; there are no folders to create by hand. The `…-uninstall-sd.zip`
  archive removes everything the same way.
- The install log shows the release version.

## Before numbered releases

- **2026-10-13** — The installer also accepts `MHI2_*_AU276_*` (Audi Q2).
- **2026-10-12** — The installer stops on any firmware train other than `MHI2_*_AU37x_*`.
- **2026-10-11** — M.I.B. V3.6+: `/mod/command.sh` is now included, because that version's
  *Run individual script* runs it.
- **2026-10-10** — The CarPlay map in the cluster pauses while the stock map is shown and
  recovers after a reconnect. The cluster plate images are found on the 1024-px HMI too.
- **2026-10-07** — CarPlay map in the Virtual Cockpit, hardware-decoded. Installing with a
  part left out removes that part from a unit that had it.
- **2026-10-03** — The instruction text is cleared at the end of a route.
- **2026-10-01** — Maneuvers are drawn live on the head unit instead of played back from
  ~90 MB of pre-drawn pictures.
- **2026-09-19** — Route guidance on the Sport cluster layout. A track without artwork
  shows the default picture instead of the previous album.
- **2026-09-07** — Fixed route guidance showing only the straight-ahead arrow.
- **2026-09-06** — Route guidance: CarPlay maneuvers in the Virtual Cockpit.
- **2026-09-03** — Fixed the missing first cover of a session and stale artwork.
- **2026-08-31** — First publication: CarPlay cover art in the cluster and the touchpad
  as a D-pad.
