# tactile-probe

Lists the USB touchscreens on this Mac, and surveys one of them: it records exactly what a touchscreen sends while a person touches it, into one JSON file for analysis. It replaces `tactile-touch-dump`, which only understood one panel.

- **`list`** prints what is attached: displays, touchscreens, their HID interfaces and report layouts. It only reads, and it shows no window.
- **`survey`** is a guided session for a person touching **one** touchscreen. Each take's instruction appears in large type on the glass of the display that touchscreen is on; every other external display says "Not this one".
- **`takes`** lists the takes and their numbers, for `--from` and `--only`.
- **`preview`** draws what the windows on the glass look like into PNG files. It opens no window and no device; it is for checking the look without running a survey.

```sh
swift build -c release --package-path Tools/tactile-probe
Tools/tactile-probe/.build/release/tactile-probe list [--json <path>]
Tools/tactile-probe/.build/release/tactile-probe survey [--touchscreen <vendor:product>] [--display <display ID or name>]
                                                       [--from <take> | --only <take,take,…>] [--out <dir>] [--step-timeout <seconds>]
                                                       [--no-windows]
Tools/tactile-probe/.build/release/tactile-probe takes
Tools/tactile-probe/.build/release/tactile-probe preview --out <dir>
swift test --package-path Tools/tactile-probe     # the tests: no device, no window, nothing left behind
```

The package has no dependencies (IOKit, CoreGraphics, AppKit). Build products in `.build/` are ignored by the repository's `.gitignore`. The test target links TactileKit's survey loader (`Tests/tactile-probeTests/SurveyFixtures.swift` is a link to `Packages/TactileKit/Tests/TactileTestSupport/SurveyFixtures.swift`), so every change to this tool's file format is checked against the code that reads it.

## Running a survey

### Which touchscreen

One touchscreen per run.
- `--touchscreen <vendor:product>` names it by its USB ID, as `list` shows it: `222a:0001` (the ILITEK), `27c0:0859` (the wch.cn).
- With only one touchscreen connected, it can be left out.
- With two connected and none named, `survey` lists them, each with the `--touchscreen` to use, and stops (exit 64). It has changed nothing by then.
- Two connected touchscreens with the same USB ID can't be told apart: unplug the one not being surveyed.

The other touchscreens are listened to in shared mode only, so that a touch on the wrong one can be named on the glass and in the take's record (`otherTouchscreenReports`). Nothing is written to them and they are never held.

### Which display shows the instructions

1. `--display <display ID or name>`: an ID (`3`), a whole name in any case (`HDMI`), or a part of exactly one name (`12.3`). A name that fits nothing, or more than one display, stops the run (exit 64) with the list of displays: the instructions never go somewhere else instead.
2. Else Tactile's pairing, from its state file `~/Library/Application Support/Tactile/state.json` (the `AppSnapshot` the app writes while it runs): the touchscreen's entry by `usbID` (and `location`, when two entries share a USB ID), its `pairedDisplayID`, and that display's `uuid`. The display must be connected now and have the same UUID. A missing or unreadable file, an unpaired touchscreen, or a display that is not connected just means "not known". Tactile removes the file when it quits, so it is there only if Tactile did not quit cleanly.
3. Else the survey asks which display the touchscreen is built into, and shows each external display's number on it while it asks. The numbers are the display IDs, the same ones `list` shows and `--display` takes. Just Enter means "not sure".
4. Not sure: every external display shows the instruction, with "Use the ILITEK-TP by ILITEK touchscreen" in place of TOUCH THIS SCREEN.

The terminal says which display was chosen and where that came from.

A display that shows another display's picture (mirrored) has no screen of its own to draw on. If the chosen display is one, the terminal says so and **no window is shown on any display**, since a "Not this one" on the display it mirrors would appear on its glass too; each take is then described in the terminal only.

### The windows on the glass

- **The display being surveyed**: dark, with a green frame round the edge. At the top, **TOUCH THIS SCREEN** (**GET READY** before Enter, when touches do nothing yet; **ALL DONE** at the end); then "Take 17 of 22 · Two-finger twist" and what to do; at the bottom, "Waiting for your touch · 21 s" with a bar that drains, then "Recording · 1.4 s", then what was got ("Got it: 2 fingers, lifted cleanly.") and the keys. The type is as large as the display allows: what to do is at least 40 points (about 9 mm on HDMI, 7 mm on the 12.3-inch strip). The footer says which take of the run it is ("2 of 7 in this run").
- **Every other external display**: a dimmed screen with a red plate, **Not this one**, and "Touch only HDMI: the screen with the green frame." The built-in display shows nothing.
- **A touch on the other touchscreen** puts a red band on the display being surveyed, "That was the OTHER touchscreen (…). Touch THIS screen.", while the take is still waiting. It goes as soon as the right touchscreen is touched.
- They are borderless, above other windows, on every Space. **They never take the keyboard**: they are non-activating panels that can't become key, and the tool never makes itself the active app, so whatever you type goes to the terminal. There is no Dock icon.
- **Clicks.** The tool reads the touchscreen at the HID level, below any window, so the windows can't change what is recorded. **Every window takes the clicks that land on it and does nothing with them.** A touchscreen that is not held clicks like a mouse: the other one always, and the wch.cn itself in takes 1–3 and 5–8. Were those clicks to reach the desktop, Finder would become the active app and the keyboard would leave the terminal. So the terminal belongs on the Mac's own display, which has no window; a terminal behind any window can't be clicked.
- `preview --out <dir>` draws these screens into PNG files, at the sizes of a set of example displays.
- `--no-windows` shows nothing on the glass: each take is described in the terminal only, as in 1.0.0. This is the way to carry on if the windows misbehave.

### The takes

There are 22. `tactile-probe takes` lists them. Each says exactly what to do and for how long. It waits up to `--step-timeout` seconds (default 30) for the first touch. With no touch by then, it records "no touch seen", says so, and waits for you, as after any take.

After each take there is a one-line summary in the terminal, such as `Got it: 2 fingers, lifted cleanly. 0.6 s, 58 reports (touchscreen 58).`, and the first part of it on the glass. Then:
- **Enter** goes on;
- **r** redoes the take. The earlier attempt stays in the file until the new one has recorded something: a redo that sees no touch, or is stopped with Ctrl-C, never loses a good take ("The earlier try is kept");
- **s** stops here (the touchscreen is put back, and what was recorded is saved).

The summary no longer says anything about the pointer. The pointer is still sampled and saved in each take's `pointer` record, for analysis.

| Take | Name (`take.id`) | State |
|---|---|---|
| 1 | `identify-circle`: one finger, slow circle, 3 s | as found |
| 2 | `two-fingers-rest`: two fingers apart, 2 s | multi-touch (after the Input Mode write) |
| 3 | `max-fingers`: as many fingers as possible, 2 s | multi-touch |
| 4 | `exclusive-circle`: one finger, slow circle, 3 s | held (touchscreen + mouse interfaces) |
| 5–8 | `corner-top-left`, `corner-top-right`, `corner-bottom-right`, `corner-bottom-left`: one tap each | multi-touch |
| 9–20 | `tap`, `double-tap`, `drag`, `rest-then-drag`, `press-and-hold`, `two-finger-scroll-flick`, `pinch`, `two-finger-tap`, `two-finger-rotate`, `three-finger-swipe-left`, `four-finger-swipe-up`, `palm` | held |
| 21 | `two-finger-flick`: two fingers flicked up, lifted while still moving | held |
| 22 | `second-finger-late`: one finger still, a second beside it half a second later, then both slide up | held |

Takes 1–20 keep the numbers, IDs and titles of the first survey (2026-11-14); tests in TactileKit find takes by them. New takes are added at the end.

**Starting from a take.** `--from <n>` runs take n to the end; `--only <list>` runs just those, in take order (`16,18`, `16-20`, `16-20,22`). Whatever the first take, the touchscreen is first put in the state it needs: switched to multi-touch for take 2 onwards (when it has an Input Mode setting), and held for the held takes. It is switched once, never back mid-run. It is held from just before the first of a stretch of held takes until just after the last, the prompts between them included, so a stray touch between takes does nothing; it is released only for takes 1–3 and 5–8, which need it unheld, and at the end. A run of held takes only, such as `--from 9` or `--from 16`, holds it for the whole run.

On a panel without Input Mode (the ILITEK), "multi-touch" takes run as found.

**When a take ends.** A take starts at the first report after the prompt. It ends at whichever comes first:
- every contact has lifted and 0.7 s have passed with none down (`endReason: "lifted"`);
- 3 s pass with contacts still down but no reports at all (`"went quiet with contacts down"`);
- 15 s have passed (`"15 s limit"`).

**What counts as "down".** On a touch interface: the contacts the reports show with the tip switch set. On a mouse interface: a button held, or the position moving. Reports from an interface the tool cannot interpret (vendor-defined) count as activity only until an interpretable report arrives.

Reports that queued up before the prompt are discarded (`staleReportsDiscarded`).

## What it changes, and how it puts things back

The tool never posts input events and never quits other apps. `list` only reads: it opens interfaces in shared mode and reads feature reports with GET_REPORT.

`survey` makes two kinds of change, both on the touchscreen being surveyed and on no other:

1. **An Input Mode write.** It writes Digitizer Input Mode (usage page 0x0D, usage 0x52) = 2 (multi-touch) before the first take from 2 onwards, if the panel has that feature.
2. **Exclusive opens.** It opens the touchscreen interface and its sibling mouse interface with `kIOHIDOptionsTypeSeizeDevice` for the held takes. If an open fails, the terminal says "FAILED" and that the recording carries on, shared with macOS: the take is still recorded, but its touches may also act on the Mac.

When the run ends, the tool closes its exclusive opens and writes back the Input Mode it found. It does the same on every way out:
- the normal end, and `s`;
- `exit()` after an error (an `atexit` handler);
- SIGINT (Ctrl-C), SIGTERM, SIGHUP and SIGQUIT. These are handled on the main run loop, which restores everything, saves what was recorded so far with `"interrupted": true`, and exits with 128 + the signal number.

Ctrl-Z (SIGTSTP) is ignored: a suspended run would keep the touchscreen held and the windows up.

Only SIGKILL or a crash skip this. macOS then drops the exclusive opens by itself. A panel left in multi-touch recovers when it is unplugged, or with `Tools/tactile-input-mode/.build/release/tactile-input-mode mouse`.

**Tactile and Touch Up.** The first thing `survey` prints is to quit them: with two programs reading a touchscreen, every touch happens twice. If a process named "Tactile" or "Touch Up" is running, it says which, and stops (exit 3) before opening any device or showing any window. It never quits the app itself.

## Things already learned (2026-11-14, no touching)

- **wch.cn `TouchScreen` (27c0:0859):** GET_REPORT for its Device Configuration feature report (0x21: Input Mode, Device Index) does **not** return the report. It echoes the USB SETUP packet (`a1 01 21 03 00 00 <wLength> 00`), followed by stale bytes from its report descriptor. IOKit sees no report ID 0x21 at the start, ignores the answer and returns its own cached value: 0 until something is written, then the last value written (the cache is in the kernel, shared by all processes).
  - So neither `tactile-input-mode` nor this tool can read this panel's real Input Mode. Every such read is flagged `valueTrusted` / `readBackTrusted: false`.
  - The write itself (SET_REPORT) returns `0x00000000`. Whether the panel obeyed shows only in what it sends afterwards: step 1 (as found) against step 2 onwards.
- **wch.cn Contact Count Maximum** reads back as 15 (feature 0x0A, raw `0a0f`), with only 10 finger collections. So hybrid mode (a frame spread over several reports) would apply if it ever reports more than 10 contacts.
- **ILITEK-TP (222a:0001):** no Input Mode. Contact Count Maximum is 10, with 10 finger collections. Its mouse interface uses report ID 0x04, the same ID as its touch report on the other interface.
- **Neither panel has** confidence, width, height, pressure, azimuth or in-range fields: only tip switch, contact ID, X and Y per finger, plus contact count and scan time per report.
- **Exclusive opens** (`kIOHIDOptionsTypeSeizeDevice`) succeeded (`0x00000000`) on the touch and mouse interfaces of both panels, run from a terminal that has Input Monitoring granted.
  - While they were held, another process (`tactile-input-mode`) could not open the touch interface (`0xe00002c5`, exclusive access), so the open really was exclusive.
  - Whether it also silences macOS's pointer is for the survey's `pointer.moved` to show.
- **The IOHIDDevice handle:** it holds one open at a time. Closing an exclusive open that was taken over a shared one closes it completely. So the tool closes the shared open, opens exclusively and registers its report callback again, and does the reverse afterwards.

## JSON schema

### Conventions

- **An absent key means "not applicable" or "the panel has no such field".** `null` is never written.
- **Hex strings are lowercase with no separators** (`"0d31ff1f..."`). IDs and codes are written as `"0x0D"`, `"0x01130000"`, `"0x00000000"`.
- **IOReturn** values are `"0x%08x"`: `0x00000000` = success, `0xe00002c5` = exclusive access (another client holds the device), `0xe00002e2` = not permitted, `0xe00002cd` = not open.
- **Times:**
  - `*Ns` fields are host time in nanoseconds: `mach_absolute_time` converted to ns. This is the same clock as the HID report timestamps, so they can be compared across takes.
  - `t` is seconds since the take's first report.
- **Normalised coordinates** `x`, `y` are `(raw - logicalMin) / (logicalMax - logicalMin)`, in 0…1. 0,0 is the panel's own origin, normally top-left.
- **Pointer coordinates** are global display coordinates in points (`CGEvent.location`). The origin is the top-left of the main display; y grows downwards. These are the same coordinates as `displays[].origin`.
- **Interface keys** name a touchscreen's HID interfaces:
  - `"touchscreen"` is the interface with the 0x0D/0x04 collection that has the most finger collections;
  - `"mouse"` is the interface with 0x01/0x02;
  - other interfaces are `"vendor-ff0a"` for a vendor-defined page, or `"hid-PPPP-UUUU"` otherwise;
  - a duplicate gets `-2`, `-3` and so on.

  Report counts, recorded reports and actions all refer to these keys.

### `list --json` (also embedded as `list` in a survey file)

```
{ environment, displays: [Display], touchscreens: [Touchscreen] }
```

**environment** fields:
- `tool`, `toolVersion`, `macOSVersion` ("26.6.2"), `macOSBuild` ("25G83"), `hardwareModel` ("Mac15,11").
- `date`: ISO 8601 with offset.
- `inputMonitoring`: `IOHIDCheckAccess(listen)` for this process, which macOS attributes to the terminal app: "granted", "denied" or "unknown".
- `accessibility`: `AXIsProcessTrusted()`.
- `terminal`: `$TERM_PROGRAM`, when set.

**Display** fields:
- `displayID`: the CGDirectDisplayID.
- `name`: `NSScreen.localizedName`; absent for a mirrored display that has no NSScreen.
- `vendorNumber`, `modelNumber`, `serialNumber`, `uuid` (`CGDisplayCreateUUIDFromDisplayID`).
- `physicalSizeMM {width, height}`: from the display's EDID.
- `pixelSize {width, height}`: backing pixels of the current mode.
- `pointSize {width, height}`: the size in global coordinates.
- `rotationDegrees`.
- `origin {x, y}`: the top-left corner in the global arrangement.
- `builtIn`, `main`, `active`, `asleep`, `refreshRateHz`, `backingScaleFactor`.
- `mirroring {inMirrorSet, mirrorsDisplayID?, alwaysInMirrorSet, primaryDisplayID}`.

**Touchscreen** (one per USB device) fields:
- `number`: 1-based, in USB location order.
- `product`, `manufacturer`, `vendorID`, `productID`, `usbID` ("27c0:0859"), `serialNumber`, `versionNumber`, `transport`, `locationID` ("0x01130000").
- `usbDevice`: a USB node, below.
- `usbHubs`: the hubs it sits behind, as USB nodes, nearest first.
- `usbController`: for example "AppleT8122USBXHCI@01000000".
- `interfaces`: a list of Interface records.
- `touchInterface`: a TouchInterface record.
- `mouseInterfaceKey`.

A **USB node** has `registryName`, `className`, `productName`, `vendorName`, `usbID`, `locationID`, `serialNumber`, `deviceClass` (9 = hub) and `speed`.

**Interface** (every HID interface of the USB device, matched by location ID) fields:
- `key`.
- `role`: "touchscreen", "mouse" or "other".
- `primaryUsage`: a UsageInfo record.
- `topLevelUsages`: a list of UsageInfo records, from `DeviceUsagePairs`.
- `usesReportIDs`.
- `reports`: a list of Report records, in descriptor order.
- `maxInputReportSize`, `maxOutputReportSize`, `maxFeatureReportSize`: as IOKit reports them.
- `reportDescriptor`: the full HID report descriptor (`kIOHIDReportDescriptorKey`), as hex.
- `reportDescriptorLength`: in bytes.
- `featureReports`: a list of FeatureReportRaw records.
- `parserCheck`: whether the tool's descriptor parser agrees with IOKit's element list. For example: "agrees with IOKit on all 42 input fields". Vendor-defined fields are compared by total size only, because IOKit folds a repeated vendor field into one long element.
- `parserWarnings`.

A **UsageInfo** record is `{page, usage, text: "0x0D/0x04", name?: "Touch Screen"}`.

A **Report** record has these fields:
- `type`: "input", "output" or "feature".
- `id`, `idHex`.
- `bytes`: the size on the wire, including the report ID byte when IDs are used.
- `decodedAs`: input reports only:
  - "touch": it has finger collections;
  - "pointer": it has buttons or an X/Y outside finger collections;
  - "other": the tool records its bytes only.
- `fingerSlots`.

A **FeatureReportRaw** record is a feature report holding Contact Count Maximum, Input Mode or Device Index, read with GET_REPORT at exactly its declared size. Its fields:
- `id`, `idHex`.
- `contains`: the usage names in the report.
- `ioReturn`.
- `length`.
- `bytes`: hex; the first byte is the report ID.
- `startsWithReportID`: `false` means the answer is malformed, and IOKit's value for the report is a cached default, not a reading (see the wch.cn note above).

**TouchInterface** (the facts the gesture engine needs) fields:
- `interfaceKey`.
- `inputReportID`, `inputReportBytes`: the input report that carries fingers.
- `fingerCollections`: logical collections with a Contact Identifier.
- `contactCountMaximum`: `{present, reportID, value, logicalMax, ioReturn, rawReport, valueTrusted}`. This is feature 0x0D/0x55, read from the panel.
- `hybridModeWouldApply`: `contactCountMaximum.value > fingerCollections`.
- `inputMode`: `{present, reportID, value, valueName, ioReturn, deviceIndexPresent, rawReport, valueTrusted}`. Values: 0 mouse emulation, 1 single touch, 2 multi-touch.
- `x`, `y`: `{bits, logicalMin, logicalMax, physicalMin, physicalMax, unit ("0x11"), unitName ("cm", "inch", "none"), exponent, sizeMM}`, where `sizeMM = (physicalMax - physicalMin) × 10^exponent × (10 for cm, 25.4 for inch)`.
- `surfaceSizeMM {width, height}`.
- `fingerFields`: `{tipSwitch, inRange, confidence, contactID, width, height, azimuth, pressure}`. Each is `{present, slots, bits?, logicalMin?, logicalMax?}`, where `slots` is how many finger collections carry it. The usages are 0x42, 0x32, 0x47, 0x51, 0x48, 0x49, 0x3F and 0x30 on page 0x0D.
- `contactCount` (0x54), `scanTime` (0x56): `{present, bits?, logicalMin?, logicalMax?}`.

### Survey file

`tactile-survey-YYYYMMDD-HHMMSS.json` (local time at the start), with the takes added when the run was not asked for all of them: `…-takes16to22.json`, `…-takes16to20+22.json`, `…-takes21+22.json`, `…-take9.json`. It is rewritten, atomically, after every take, so a crash loses at most one take.

**What changed in 1.1.0** (2026-11-14). Still `formatVersion: 1`: nothing was renamed, renumbered or removed, and every addition is a key that older files simply lack. A file from 1.0.0 reads with 1.1.0's types, and a file from 1.1.0 reads through TactileKit's loader (`SurveyFixtures`); the tool's tests check both.
- One touchscreen is surveyed per run. The others are still listed, each with a section whose `status` and `identifiedBy` are "not chosen" and no takes.
- Takes 21 (`two-finger-flick`) and 22 (`second-finger-late`) are new. A run can start past take 1 (`--from`, `--only`), so a section's takes may begin at any number; `number` is always the take's number in the catalogue, never its place in the run.
- New keys: `settings.arguments`, `settings.takesSelected`, `touchscreens[].display.source`.
- New values: `identifiedBy` "named with --touchscreen", "the only touchscreen connected" and "not chosen"; `status` "not chosen".
- `summary` no longer mentions the pointer. The `pointer` record is unchanged.
- `conflictingApps` is always empty: the tool now refuses to start while Tactile or Touch Up runs.
- `endedBecause` names the takes the run was asked for, and how it ended. The endings 1.0 also had still begin with its words ("finished", "stopped by signal N", "still running"); the new one, after `s`, begins "stopped by the person". `completed` is true only when every take asked for was run: stopping with `s` leaves it false.
- `display.choices[].number` is the display's ID, as `list` and `--display` use it (1.0 numbered the displays 1, 2, 3…).
- A redone take replaces the earlier attempt only once the new attempt has recorded; otherwise the earlier one stays.

```
{
  format: "tactile-probe survey", formatVersion: 1,
  environment,                       // as in list
  settings: { stepTimeoutSeconds, takeLimitSeconds: 15, liftQuietSeconds: 0.7, quietWithContactsDownSeconds: 3,
              arguments: [String],   // 1.1.0: the arguments after `survey`, as typed
              takesSelected: [Int] },// 1.1.0: the take numbers the run was asked for
  list,                              // exactly what `list --json` writes
  conflictingApps: [String],         // 1.0.0: Touch Up / Tactile processes seen at the start, before the person quit
                                     // them. Since 1.1.0 always empty: the survey does not start while one runs
  touchscreens: [TouchscreenSurvey], // one per list.touchscreens entry, same order and number
  restore: [Action],                 // what the final clean-up (or an interruption) had to put back
  completed: Bool,                   // since 1.1.0: every take asked for was run (false after `s`)
  interrupted: Bool,
  endedBecause: String               // 1.0.0: "finished" | "stopped by signal N" | "still running". Since 1.1.0 those
                                     // openings, and "stopped by the person" for `s` (new), then the run:
                                     // "finished: takes 16 to 22 (7 takes)", "stopped by the person
                                     // after take 18, of takes 16 to 22 (7 takes)", "stopped by signal 2 during take 17, of …"
                                     // (or "after take 17", "before the first take"), "still running: all 22 takes"
}
```

**TouchscreenSurvey** fields:
- `number`, `locationID`, `name`.
- `identifiedBy`:
  - since 1.1.0: "named with --touchscreen", "the only touchscreen connected", or "not chosen" (another touchscreen was surveyed in this run);
  - in 1.0.0 files: "touch", "no touch seen; took the next touchscreen in list order" or "not reached".
- `status`: "done", "skipped by the person" (stopped with `s`), "interrupted", "not reached", or (since 1.1.0) "not chosen".
- `display`: the display the touchscreen is on, which showed the instructions. Absent when none was settled:
  - `source` (since 1.1.0): "--display", "state file" (Tactile's pairing) or "question" (the person's answer). Absent in 1.0.0 files, where it is always the person's answer;
  - `answer`: what the person typed, at the question or as `--display`; "" means not sure, or nothing typed (`source` "state file");
  - `displayID`, `name`: the chosen display; absent when the person was not sure, and then every external display showed the instructions;
  - `choices`: `[{number, displayID, name}]`, the numbered list the question showed, which is every non-built-in display; empty when no question was asked. Since 1.1.0 `number` is the display ID; in 1.0.0 files it counts from 1.
- `inputModeFound`, `inputModeFoundName`: as IOKit read it before any change.
- `inputModeFoundTrusted`, `inputModeFoundRaw`: whether that reading really came from the panel, and the raw GET_REPORT bytes.
- `actions`: a list of Action records, in order.
- `takes`: a list of Take records, in order, one per take. A redone take replaces the earlier attempt, in its place, once the new attempt has recorded; a redo that saw no touch, or was interrupted, leaves the earlier recording in the file (since 1.1.0; 1.0 dropped it at once). `attempt` counts the tries.

An **Action** records a change the tool made, or tried to make. Its fields:
- `kind`: one of these:
  - "shared open": listening; one per interface at the start;
  - "input mode write" (to 2);
  - "input mode write skipped": no Input Mode, already 2, or unreadable;
  - "exclusive open";
  - "exclusive close";
  - "shared reopen": listening again after an exclusive close;
  - "input mode restore": back to `inputModeFound`.
- `touchscreen`: its location ID.
- `interface`: an interface key.
- `take`: the take it came before (opens and writes) or after (closes); absent for start and end.
- `ioReturn`: "none" when nothing was sent.
- `ok`: the call succeeded. For Input Mode, the read-back also matched, unless the read-back cannot be trusted.
- `value`: the value written.
- `readBack`: what IOKit reads afterwards.
- `featureReport`: the raw Device Configuration report as GET_REPORT returned it afterwards.
- `readBackTrusted`.
- `note`.

**Take** fields:

| Field | Meaning |
|---|---|
| `id`, `number` (1–22), `title`, `prompt` | Which take, and the exact words shown. `number` is the take's number in the catalogue |
| `mode` | "as-found", "multi-touch" (Input Mode switched and reading 2) or "exclusive" (at least one interface held exclusively) |
| `inputMode` | Input Mode in effect as IOKit reads it (see `inputModeFoundTrusted`); absent without Input Mode |
| `exclusiveInterfaces` | Interface keys held exclusively during the take |
| `attempt` | 1, or more after a redo |
| `result` | "recorded", "no touch seen" or "interrupted" |
| `endReason` | "lifted", "went quiet with contacts down", "15 s limit" or "interrupted"; absent when no touch was seen |
| `summary` | The plain-words line shown in the terminal. Since 1.1.0 it says nothing about the pointer, and names the other touchscreen when that one was touched |
| `promptedAtNs`, `startedAtNs`, `endedAtNs` | Prompt shown; first report; take ended |
| `waitedSeconds` | From the prompt to the first report |
| `durationSeconds` | From the first report to the end of the take (includes the 0.7 s quiet) |
| `reportSpanSeconds` | From the first report to the last |
| `reportCounts` | `{interfaceKey: count}`, for the surveyed touchscreen only |
| `otherTouchscreenReports` | Reports from another touchscreen during the take (ignored). Above 0, the wrong screen was touched |
| `staleReportsDiscarded` | Reports time-stamped before the prompt |
| `pointer` | The system pointer, sampled every 50 ms from the prompt to the end. See the pointer table below |
| `facts` | Derived facts, below. Absent when no touch was seen |
| `tap` | Corner takes only: `{touch?: {x, y}, touchSamples, mouse?: {x, y}, mouseSamples}`. These are the median normalised positions of the first down contact on the touch interface, and of the mouse position while a button was held |
| `reports` | Every input report, in arrival order. See Report record below |

The `pointer` record has these fields:

| Field | Meaning |
|---|---|
| `from`, `to` | Where the pointer was at the prompt and at the end |
| `moved` | Whether it moved more than 0.5 point at any time |
| `maxDistance` | The furthest it got from `from` |
| `endDisplayID`, `endDisplayName` | The display it ended on |
| `samples` | `[[secondsSincePrompt, x, y]]`, one entry each time the position changed |

**facts** fields:
- `interfacesReporting`: interface keys that sent at least one report.
- `reportRateHz {interfaceKey: Hz}`: (n − 1) / (last − first) per interface.
- `contactIDsSeen`: contact IDs seen with the tip down, on touch interfaces.
- `maxContactsDown`: the most contacts down in one frame.
- `maxContactCountField`: the highest Contact Count value reported.
- `fingersChangeSlots`, `slotChanges`: whether a contact that stayed down appeared at a different position in the frame, and how often. The position is the slot index plus, in hybrid mode, the slots already received in that frame.
- `liftedWithTipUpReport`: contacts whose lift was reported with tip switch 0.
- `liftedWithoutTipUpReport`: contacts that just disappeared from a later complete frame.
- `stillDownAtEnd`: contacts never lifted in the reports. A panel that "goes quiet" shows here, or with `endReason: "went quiet with contacts down"`.
- `finalTipUp`: "every contact", "some" or "none", from the three counts above.
- `lastTouchReportHadNoContacts`: whether the last touch report had no tip down, that is, a final empty report arrived.
- `hybridObserved`: a frame was split across reports. That shows as a Contact Count above the slot count, or a report with Contact Count 0 arriving mid-frame (as Touch Up's reader, TactileCore's HIDInterpreter, handled it before 0.2.0 removed it).
- `touchFramesSplitAcrossReports`: how many continuation reports arrived.
- `mouseButtonsSeen`: OR of the button bits on pointer interfaces (bit 0 = button 1).
- `mouseButtonReleased`.

A **Report record** (one per input report) has these fields:
- `t`, `hostTimeNs`.
- `interface`: the interface key.
- `reportID`.
- `length`: in bytes.
- `bytes`: the full raw report as delivered by `IOHIDDeviceRegisterInputReportWithTimeStampCallback`, as hex. It starts with the report ID byte when the interface uses IDs.
- `contactCount`, `scanTime`: when the report has them.
- `fingers`: touch reports only. A list of slots, `{slot, id?, tip?, x?, y?, rawX?, rawY?, inRange?, confidence?, width?, height?, pressure?, azimuth?}`.
  - It lists the slots that carry data: tip down, any non-zero field, or an index below the report's Contact Count. Every other slot was all zeros; `bytes` holds everything.
- `pointer`: pointer reports only, `{buttons?, x?, y?, rawX?, rawY?, dx?, dy?, wheel?, tip?, inRange?}`.
  - `x`, `y` (normalised) and `rawX`, `rawY` are for absolute axes; `dx`, `dy` are for relative ones.

### Replaying a panel without touching it

Everything needed to rebuild a panel's input exactly is in the file:
- each interface's `reportDescriptor`, which gives the layout;
- its `featureReports` (Contact Count Maximum, Device Configuration);
- every input report, with `interface`, `reportID`, `length`, `bytes` and `hostTimeNs`.

To replay a take, feed each report's `bytes` to a parser built from that interface's descriptor, at the recorded `hostTimeNs` spacing. The parsed `fingers` and `pointer` are a convenience and a cross-check; the raw bytes are the record.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Done |
| 1 | Could not write output |
| 2 | No touchscreen found, or the one named with `--touchscreen` is not connected (`survey`) |
| 3 | Tactile or Touch Up is running: nothing was opened or changed (`survey`) |
| 64 | Bad command line; or two touchscreens connected and none named; or `--display` fits no display, or several |
| 128 + n | Stopped by signal n, after putting things back |
