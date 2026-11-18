# Notices and credits

Tactile is written by Cristian Moldovan, and licensed under the GNU General Public License, version 3: see [`LICENSE`](LICENSE). The name "Tactile" and its icon are not covered by that licence: see [`TRADEMARKS.md`](TRADEMARKS.md). This file says what came from other projects, and on what terms.

## Touch Up

**Tactile was inspired by [Touch Up](https://github.com/shueber/Touch-Up) by Sebastian Hueber (MIT).** It began as a fork of Touch Up 1.1. Touch Up's code left Tactile in 0.2.0 and its icon in 0.4.0. What remains of it:

- the skeleton of the Xcode project file, and the workspace files Xcode generates;
- the accent colour's values, in `Tactile/Assets.xcassets/AccentColor.colorset`;
- one fact: what the trackpad's zoom event holds. It is gesture event type 29, with the magnification as a double in fields 113, 114, 116 and 118, the integers 248 in field 50, 4 in 101 and 8 in 110, and the phase in 132. `EventSender.pinch` writes it in its own way, and puts the gesture's phase in 132 where Touch Up put the touch's.

None of that is a substantial portion of Touch Up. Its copyright and permission notice is kept here all the same, as a courtesy:

```
MIT License

Copyright (c) 2024 Sebastian Hueber

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Facts learned from other projects

Tactile posts events that Apple doesn't document: the trackpad's zoom and rotate gestures, and the Dock's swipe between Desktops. What those events hold was learned from the projects below. Tactile uses only **facts** from them: event types, field numbers, values, timings and measurements, which any program needs to work with macOS.

No code or comment text from these projects is in Tactile. `DockSwipeSender.swift`, `EventSender.swift`, `CursorVisibility.swift` and `ScrollMatch.swift` were written for Tactile. On 2026-11-18 every source file of the Mac app and its tools was compared with these projects' sources: runs of code tokens, comments and string literals. They share nothing but those facts and ordinary uses of Apple's APIs. So none of these projects' licence terms applies to Tactile, the Mac Mouse Fix licence's included. They are credited here for what they found.

| Project | Licence | What Tactile uses from it |
|---|---|---|
| [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix), Noah Nuebling | The MMF License | The Dock swipe's fields for macOS 12 to 26: event type 30 in field 55, the Dock swipe (23) in 110, the phase in 132 and again in 134, the progress in 124, the speed at the end in 129 and 130, with an empty gesture event (type 29) beside it. Posting at the session tap. Sending the end again 0.2 s later, as the Dock sometimes misses it. The 63-point gap between Spaces, and progress of n/(n−1) for each Space (2 with one Space), which make the Desktops follow the fingers. Counting a display's Spaces through the window server's list of managed display Spaces. That more than one event every 8 ms or so makes the Dock fall behind. That a large progress can skip two Spaces, so Tactile keeps it to one. That macOS 27 reads only an IOHID payload, which Tactile doesn't build: there it uses the keyboard shortcuts. |
| [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher), jurplel | MIT | The speed fields (129, 130) and the phase repeated in 134; the empty gesture event beside the swipe. That from macOS 27.2 a synthetic swipe works only while the trackpad's "Swipe between full-screen applications" is on, which Tactile checks. That going past the last Space can wedge the Dock. |
| [yabai](https://github.com/asmvik/yabai), Åsmund Vikane | MIT | A short form of the Dock swipe (fields 55, 110, 123, 124, 129 and 132), posted at the session tap, with the pointer on the display whose Spaces move. |
| [FasterSwiper](https://github.com/mgbowen/FasterSwiper), mgbowen | Apache-2.0 | That ending or cancelling a swipe is the sender's choice: ended moves on to the next Space, cancelled slides back. Progress of count/(count−1) for each Space. |
| [Space Rabbit](https://github.com/Tahul/space-rabbit), Tahul | MPL-2.0 | Making the end event before posting the beginning, so a failure can't leave the Dock between two Desktops. |
| tbodt and mogenson, in [Hammerspoon pull request #3859](https://github.com/Hammerspoon/hammerspoon/pull/3859) | — | What a real trackpad's swipe sends, which fields matter, and how a swipe left open gets stuck. |
| Calf Trail Software's `TouchEvents.c`, Nathan Vander Wilt, shipped in [Hammerspoon](https://github.com/Hammerspoon/hammerspoon)'s `eventtap` | GPL-2.0-or-later | The rotate gesture: event type 29, the subtype in field 110 (5 for rotation, 8 for zoom), the phase in 132, and the rotation in degrees in 114. |
| Apple's [IOHIDFamily](https://github.com/apple-oss-distributions/IOHIDFamily), and Hammerspoon's copy of its `IOHIDEventTypes.h` | APSL 2.0 | The IOHID event types (the Dock swipe 23, rotation 5, zoom 8), the Dock's gesture flavour (3) and the phase values (1, 2, 4 and 8). |
| WebKit's [`CoreGraphicsTestSPI.h`](https://github.com/WebKit/WebKit/blob/main/Tools/TestRunnerShared/spi/CoreGraphicsTestSPI.h), Apple | BSD-2-Clause | Apple's names for the event fields 55 and 110 to 148, which Tactile's comments use. |
| [Visual Studio Code](https://github.com/microsoft/vscode), Microsoft | MIT | How its editor turns a scroll event into pixels (`wheelDeltaY / 120`, a sensitivity of 50, each event rounded up), which `ScrollMatch` matches in the editors built on it. |
| [MouseDragFix](https://github.com/channelramble/MouseDragFix), channelramble | MIT | Studied for its route to macOS 27's payload, which Tactile doesn't use. Nothing taken beyond confirming the facts above. |
| [Mousse](https://github.com/MinhQuang28/Mousse), MinhQuang28 | PolyForm Noncommercial 1.0.0 | Studied. Nothing taken. |

One more fact Tactile uses is long known and in many projects, Mac Mouse Fix among them: the WindowServer connection property `SetsCursorInBackground` lets an app hide the pointer while another app is active (`CursorVisibility.swift`).
