# Tactile

**Multi-touch for external touchscreens on macOS.**

macOS has no touchscreen driver. Most USB touch panels still work as a mouse: they report one pointer, which macOS puts on a screen of its own choosing. You get no multi-touch, and touches often land on the wrong display. Tactile reads the panel's own touch reports and turns them into clicks, drags, scrolling, zooming and swipes, on the display you pair the panel with. It lives in the menu bar.

## Download

Download Tactile from **[tactilemac.com](https://tactilemac.com)**. Open the disk image, drag Tactile into Applications, and open it. The official build is signed with the Developer ID, notarized by Apple, and updates itself.

It needs:

- **macOS 14** or later;
- a **USB touchscreen**;
- **Accessibility** access, to click and scroll for you;
- **Input Monitoring**, which macOS may ask for when Tactile reads a touchscreen. macOS often answers it from the Accessibility permission without asking.

## What it does

- Tap to click, and double-tap.
- One finger drags or scrolls, depending on what is under it. Rest it a moment first to drag anything.
- Two-finger scroll with momentum, pinch to zoom, and two-finger rotate.
- Two-finger tap, or a long press, for a secondary click.
- Three- and four-finger swipes for Spaces and Mission Control.
- Palm rejection, and touches starting near the edge can be ignored.
- Touch circles show where each finger lands. The pointer goes back where it was.
- Each touchscreen is paired with its own display, and set up by touch: you click the screen, touch it, then touch four targets.
- Several touchscreens at once. A panel that stays a mouse works as a one-finger touchscreen.
- A gesture tester, to try every gesture a touchscreen can make.

Tactile has been used with an ILITEK panel (USB ID `222a:0001`, multi-touch) and a wch.cn strip (`27c0:0859`, which stays a mouse, so one finger). Other touchscreens that follow the HID digitizer standard should work. If yours doesn't, see [below](#if-your-touchscreen-doesnt-work).

Tactile collects nothing. The official build asks tactilemac.com for updates, giving its own version and build. It sends a touchscreen report only when you check a touchscreen and press **Send**.

## First run

1. Open Tactile. It lives in the menu bar; there is no Dock icon.
2. **Accessibility.** If access is missing, Settings opens with the warning "Accessibility access missing" and a button, **Open Accessibility Settings…**. Until access is granted, Tactile leaves every touchscreen to macOS.
3. **Set up the touchscreens.** For a touchscreen Tactile hasn't met, a small window offers **Set Up…**. On the screen that has the touchscreen, click **This One**, then touch that screen. Then touch the four targets, confirm the size, check, and click **Done**. **Set Up Touchscreens…** in the menu starts it again later.
4. **Try the gestures** with **Gesture Tester…**, under a touchscreen in the menu.

If Tactile says Accessibility access is missing while it is switched on in System Settings, macOS has kept an entry for a copy signed differently. Remove Tactile from both lists in System Settings › Privacy & Security (Accessibility, and Input Monitoring) with −, and add it again with +.

Quit any other program that reads the touchscreen, such as Touch Up, before you use Tactile: two programs reading one touchscreen would make every touch happen twice. Tactile warns you if Touch Up is running.

Tactile keeps its settings in `~/Library/Application Support/Tactile/settings.json`. Its log is in the unified log:

```sh
/usr/bin/log stream --level info --predicate 'subsystem == "com.crissmoldovan.tactile"'
```

**Copy diagnostics**, in General, puts a description of Tactile's state on the clipboard, for a bug report. It includes the touchscreens' serial numbers: remove them before you post it.

## If your touchscreen doesn't work

Open **Touchscreen Check**, below General in Settings. It lists every connected touchscreen, and the touch devices Tactile doesn't list at all (digitisers, and touchscreens that only act as a mouse), each with **Check…**. A touchscreen's pane has **Check This Touchscreen…** under its On switch, and so do its details beside the menu. If touch doesn't work right while you set up a touchscreen, calibrate its corners or test it, the set-up screens offer the check too: click **Check This Touchscreen…**, or **Check…** beside the touchscreen when you set up several. The set-up ends first, and whatever was already set up stays.

The check takes a minute. Tactile reads what the touchscreen says about itself, takes it as it always does, and asks you to touch it with one, two and five fingers. It ends with a verdict: works fully, works with one finger, or doesn't work.

You then see every file of the report, and can open each one. Nothing leaves your Mac until you press **Send**. The official build sends it to tactilemac.com with the email you type, so we can reply, and nothing is filed until you confirm by email. The report holds no serial number, and nothing about your Mac beyond its model, its macOS version and how many displays it has.

Any other build, or the official one while sending isn't switched on, offers **Save Report…** instead. Attach the saved zip to a [touchscreen report](https://github.com/crissmoldovan/tactile-mac/issues/new?template=touchscreen_report.yml) on GitHub. GitHub issues are public.

## Building from source

You need macOS 14 or later and Xcode 27 or later.

```sh
xcodebuild -project Tactile.xcodeproj -scheme Tactile -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Tactile.app
```

**Signing.** The official releases are signed with the Developer ID (since 0.6.1) and notarized. A build from source is signed **ad hoc** ("Sign to Run Locally"), so anyone can build it with no Apple account or certificate (`Config/Signing.xcconfig`), and the build says so with a warning. An ad hoc signature changes with every build, so macOS asks again for Accessibility and Input Monitoring after each one: remove Tactile from both lists and add it again, as above.

To sign with a certificate of your own, put the settings in `Config/Signing.local.xcconfig`. Git ignores it, and the project reads it last. For example, with your Apple Development certificate:

```
CODE_SIGN_STYLE = Automatic
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = <your team ID>
```

Quit any other copy of Tactile before you run a build. A second Tactile quits by itself at launch.

All the logic is in the Swift package `Packages/TactileKit`; the Xcode target is only the entry point. Its tests need no hardware and open no window:

```sh
swift test --package-path Packages/TactileKit
```

`Tools/install.sh` builds Release and installs it into `/Applications`. It signs with the official Developer ID, so it is for the maintainer's Macs. To use a build of your own day to day, copy it into Applications yourself.

## Updates

The official build updates itself. **Check for Updates…** in the menu asks tactilemac.com now, and **Check for updates automatically**, in General, asks once a day. When a newer version is known, the menu offers **Update to <version>…**, with its notes.

Before it installs anything, Tactile checks the download itself; the website is only a courier. The update must carry a valid Ed25519 signature from one of the update keys built into the app. The app inside must be signed with the official Developer ID, under Tactile's bundle identifier, and be the version offered. Any failure stops the update. [`docs/updates-contract.md`](docs/updates-contract.md) has the details.

**A build from source doesn't update itself.** Only the official build does: Tactile's bundle identifier, signed with the Developer ID. Any other build, ad hoc or a fork's, asks no site, and the menu says "Updates are off in this build of Tactile." So an official release never replaces a build of your own.

## Tools

Three small Swift packages, for looking at touchscreens. Quit Tactile before you use them. Each prints its usage with `--help`.

- **`Tools/tactile-probe`** lists the touchscreens and displays with their HID facts, and records exactly what a touchscreen sends while you touch it. See [`Tools/tactile-probe/README.md`](Tools/tactile-probe/README.md).
- **`Tools/tactile-input-mode`** shows and switches a touchscreen's Input Mode (mouse emulation or multi-touch). It writes only the standard digitizer settings the panel declares, and puts mouse emulation back at the end.
- **`Tools/tactile-release`** is the update key's tool, for releases ([`Tools/RELEASING.md`](Tools/RELEASING.md)).

```sh
swift run --package-path Tools/tactile-probe tactile-probe list
swift test --package-path Tools/tactile-probe
```

TactileKit also has a check of its device layer: `swift run --package-path Packages/TactileKit tactile-devices-check list` (it opens nothing).

## Repository layout

| Path | What it holds |
|---|---|
| `Tactile.xcodeproj`, `Tactile/` | The app's Xcode project and entry point, its asset catalogue (the icon and the menu-bar glyphs) and entitlements. `Tactile/IconSources/` holds the icon's drawings |
| `Packages/TactileKit/` | Everything else: `TactileReading` (reports into contacts), `TactileScreens` (touchscreens, displays, pairing, settings), `TactileGestures` (the gesture engine), `TactileOutput` (events, pointer, circles), `TactileDevices` (the USB side, and the touchscreen check), `TactileUpdates` (the updater), `TactileSupport` (the check's report, and sending it) and `TactileApp` (the model and the interface) |
| `Config/` | Signing and the update settings |
| `Fixtures/surveys/` | Two recorded panel surveys, which the tests replay. Their serial numbers and display IDs are placeholders |
| `Tools/` | `install.sh`, `release.sh` and the three tool packages |
| `docs/` | The updates contract, and the touchscreen report the site takes |

## Licence

Tactile is free software, under the [GNU General Public License, version 3](LICENSE). You may use, study, share and change it; if you share a changed version, you share its source under the same licence.

**The name and the icon are not part of that licence.** "Tactile" and the Tactile icon (the Ripple) are Cristian Moldovan's marks. A fork must use another name and icon, and its own bundle identifier, update site and keys. See [`TRADEMARKS.md`](TRADEMARKS.md).

Tactile was inspired by [Touch Up](https://github.com/shueber/Touch-Up) by Sebastian Hueber (MIT). None of Touch Up's code or artwork is left in Tactile. [`NOTICE.md`](NOTICE.md) says what came from it and from other projects.

## Contributing

Bug reports, touchscreen reports and ideas are welcome, as [issues](https://github.com/crissmoldovan/tactile-mac/issues/new/choose). This project doesn't take pull requests. See [`CONTRIBUTING.md`](CONTRIBUTING.md). To report a security problem, see [`SECURITY.md`](SECURITY.md).
