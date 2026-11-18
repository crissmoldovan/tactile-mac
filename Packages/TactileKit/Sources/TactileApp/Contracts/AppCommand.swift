import Foundation
import TactileGestures
import TactileScreens

public enum AppCommand: Equatable, Sendable {
    case setOn(Bool)
    case setTouchscreenOn(TouchscreenID, Bool)
    case setWhenOff(TouchscreenID, WhenOff)
    case rename(TouchscreenID, to: String?)          // nil or empty: back to the device's own name
    case pair(TouchscreenID, displayID: UInt32)      // a display that is connected now
    case unpair(TouchscreenID)
    case setOrientation(TouchscreenID, Orientation)
    case setDiagonal(TouchscreenID, inches: Double?)
    case forget(TouchscreenID)                       // only a touchscreen that is not connected
    case renameDisplay(uuid: String, to: String?)
    case setDebugLogging(Bool)
    case askForAccessibility
    case setOneFinger(TouchscreenID, OneFingerMode?)  // nil: back to the default
    case setPointerReturn(TouchscreenID, PointerReturn)
    case setShowsCircles(TouchscreenID, Bool)
    case setGestures(TouchscreenID, GestureOptions)
    case setRejection(TouchscreenID, RejectionRules)
    case copyBehaviour(from: TouchscreenID, to: TouchscreenID)
    case resetBehaviour(TouchscreenID)
    case clearCalibration(TouchscreenID)                // alignment back to the whole glass
    /// From 0.5.0, `beginSetUp(id, .full)` is read as `beginSetUpMode`. `.calibrate` and `.test` are
    /// unchanged; sent while set-up mode is on, they run inside the mode and return to its overview.
    case beginSetUp(TouchscreenID, SetUpPurpose)
    case setUpConfirmSize(inches: Double?)              // nil: as reported
    case setUpRedo                                      // from check, back to the corners
    case setUpDone
    /// Leaves the set-up: set-up mode, or a Calibrate/Test flow outside it. **Finish** and Esc send it.
    case cancelSetUp
    case declineSetUp(TouchscreenID)                    // "Not Now": don't offer again
    /// Begins set-up mode: the menu's **Set Up Touchscreens…**, the first-run window's **Set Up…**,
    /// a pane's **Set Up by Touch…**.
    case beginSetUpMode
    /// In set-up mode, chooses the display with this ID: a card's **This one** (or **Set Up Again
    /// Here** on a card that has a touchscreen).
    case setUpChoose(displayID: UInt32)
    /// In set-up mode, a flow card's **Back**: ends this touchscreen's flow, stores nothing, and
    /// returns to the overview.
    case setUpBack
    case setRecordsFrames(Bool)
    case copyDiagnostics
    case setSwipesFollowFingers(Bool)
    case setLaunchAtLogin(Bool)
    case openLoginItemsSettings
    /// Opens the gesture tester for this touchscreen, on the display it is paired with. One tester
    /// at a time: opening it for another touchscreen moves it.
    case openGestureTester(TouchscreenID)
    /// Closes the gesture tester: its close button, or Esc.
    case closeGestureTester
    /// The tester's **Let swipes through**: true lets the touchscreen's three- and four-finger swipes
    /// be done; false (the default each time it opens) records them and does not do them.
    case setGestureTesterPerformsSwipes(Bool)
    /// The tester's **Clear**: empties `recent` and counts `seen` again from nothing.
    case clearGestureTester
    /// The touchscreen check is about to take this touchscreen: Tactile lets go of it until
    /// `endSupportCheck`, so the check can take it exactly as Tactile does. Refused while a set-up runs.
    case beginSupportCheck(TouchscreenID)
    /// The check has let the touchscreen go: Tactile takes it back.
    case endSupportCheck
}
