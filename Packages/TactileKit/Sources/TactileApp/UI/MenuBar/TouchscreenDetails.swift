// A touchscreen's details, beside the menu-bar panel while its row is chosen: its name and a line
// that sums it up; On, One finger and Show touches; Gesture Tester…; Calibrate Corners… and Test,
// or Set Up Touchscreens… for one that isn't set up; Settings for <name>…. For one Tactile can't
// use, why, and its pane; for one that isn't connected, its pane alone. What each shows, what
// enables it and what it sends is `MenuTouchscreenDetails`, the pane's own rules.

import AppKit
import SwiftUI
import TactileScreens

/// What the details do beyond sending a command: close the menu (and the details with it) once a
/// tester, a set-up or Settings takes over; open Settings on a pane.
struct TouchscreenDetailsActions {
    var closeMenu: @MainActor () -> Void
    var openSettings: @MainActor (SidebarItem) -> Void

    /// For renders: nothing happens.
    static let none = TouchscreenDetailsActions(closeMenu: {}, openSettings: { _ in })
}

/// The details window's content for one touchscreen, following the model's steady snapshot, so the
/// tester's feed never draws it again. Nothing once the touchscreen is gone (the menu's presenter
/// closes the window).
struct TouchscreenDetailsRoot<Model: AppModel>: View {
    let model: Model
    let id: TouchscreenID
    var actions: TouchscreenDetailsActions

    var body: some View {
        let snapshot = model.steadySnapshot
        if let touchscreen = snapshot.touchscreens.first(where: { $0.id == id }) {
            TouchscreenDetailsView(
                details: MenuTouchscreenDetails(touchscreen, in: snapshot), perform: { model.perform($0) },
                actions: actions)
        }
    }
}

/// The details, drawn as the panel draws its rows: drawn here, and rendered in tests.
struct TouchscreenDetailsView: View {
    var details: MenuTouchscreenDetails
    var perform: PerformCommand
    var actions: TouchscreenDetailsActions

    static let width: CGFloat = 288

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(details.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(details.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.top, 2)
            .padding(.bottom, 4)

            if let unusable = details.unusable {
                PanelSeparator()
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(Wording.menuCannotBeUsed(unusable))
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
            }

            if let controls = details.controls {
                PanelSeparator()
                DetailsSwitchRow(title: Wording.on, value: controls.on.isOn, isEnabled: controls.on.isEnabled) {
                    perform(details.onCommand($0))
                }
                HStack {
                    Text(Wording.oneFingerLabel)
                    Spacer(minLength: 12)
                    Picker(Wording.oneFingerLabel, selection: Binding(
                        get: { controls.oneFinger.choice },
                        set: { option in details.oneFingerCommand(option).map { perform($0) } }
                    )) {
                        ForEach(OneFingerPicker.options, id: \.self) { option in
                            Text(controls.oneFinger.title(option)).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                .foregroundStyle(controls.behaviourIsEnabled ? .primary : .tertiary)
                .disabled(!controls.behaviourIsEnabled)
                .padding(.horizontal, 10)
                .frame(minHeight: 26)
                DetailsSwitchRow(
                    title: Wording.showTouches, value: controls.showsTouches, isEnabled: controls.behaviourIsEnabled
                ) {
                    perform(details.showTouchesCommand($0))
                }

                PanelSeparator()
                PanelRowButton(title: Wording.gestureTester, isEnabled: controls.gestureTester == .available) {
                    actions.closeMenu()
                    GestureTesterWindow.open(details.id, perform: perform)
                }
                .help(controls.gestureTester.reason.map(Wording.gestureTesterUnavailable) ?? "")
                if let reason = controls.gestureTester.reason {
                    PanelReason(text: Wording.gestureTesterUnavailable(reason))
                }
                switch controls.setUp {
                case .calibrateAndTest(let availability):
                    let help = availability.reason.map(Wording.setUpUnavailable) ?? ""
                    HStack(spacing: 0) {
                        PanelRowButton(title: Wording.calibrateCorners, isEnabled: availability == .available) {
                            perform(details.calibrateCommand)
                            actions.closeMenu()
                        }
                        .help(help)
                        PanelRowButton(title: Wording.test, isEnabled: availability == .available) {
                            perform(details.testCommand)
                            actions.closeMenu()
                        }
                        .help(help)
                        .frame(width: 84)
                    }
                    if let reason = availability.reason {
                        PanelReason(text: Wording.setUpUnavailable(reason))
                    }
                case .setUpTouchscreens(let availability):
                    PanelRowButton(title: Wording.setUpTouchscreens, isEnabled: availability == .available) {
                        perform(MenuTouchscreenDetails.setUpCommand)
                        actions.closeMenu()
                    }
                    .help(availability.reason.map(Wording.setUpUnavailable) ?? "")
                    if let reason = availability.reason {
                        PanelReason(text: Wording.setUpUnavailable(reason))
                    }
                }
            }

            if let support = details.support?.whileFinishing(SupportChecksFinishing.shared.isFinishing(details.id)),
               let target = details.supportTarget {
                PanelSeparator()
                PanelRowButton(title: Wording.helpMeSupport, isEnabled: support == .available) {
                    actions.closeMenu()
                    SupportCheckWindow.open(target, perform: perform)
                }
                .help(support == .available ? "" : Wording.supportUnavailable(support))
                if support != .available {
                    PanelReason(text: Wording.supportUnavailable(support))
                }
            }

            PanelSeparator()
            PanelRowButton(title: Wording.settingsFor(name: details.name)) {
                actions.openSettings(details.pane)
            }
        }
        .padding(6)
        .frame(width: Self.width)
    }
}

/// A switch in the details: its title, and the switch on the right, as the panel's Tactile switch.
struct DetailsSwitchRow: View {
    var title: String
    var value: Bool
    var isEnabled: Bool
    var set: @MainActor (Bool) -> Void

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(isEnabled ? .primary : .tertiary)
            Spacer(minLength: 12)
            Toggle(title, isOn: Binding(get: { value }, set: { set($0) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(!isEnabled)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 26)
    }
}

/// The same details as a submenu, for the plain menu (`MenuBarMenu`): checkmarks for the switches,
/// the One finger choices as a submenu of their own, each reason as a line beneath its item.
struct TouchscreenDetailsMenu: View {
    var details: MenuTouchscreenDetails
    var perform: PerformCommand
    var openSettings: @MainActor (SidebarItem) -> Void

    var body: some View {
        Text(details.summary)
        if let unusable = details.unusable {
            Text(Wording.menuCannotBeUsed(unusable))
        }
        if let controls = details.controls {
            Divider()
            Toggle(Wording.on, isOn: Binding(get: { controls.on.isOn }, set: { perform(details.onCommand($0)) }))
                .disabled(!controls.on.isEnabled)
            Picker(Wording.oneFingerLabel, selection: Binding(
                get: { controls.oneFinger.choice },
                set: { option in details.oneFingerCommand(option).map { perform($0) } }
            )) {
                ForEach(OneFingerPicker.options, id: \.self) { option in
                    Text(controls.oneFinger.title(option)).tag(option)
                }
            }
            .disabled(!controls.behaviourIsEnabled)
            Toggle(Wording.showTouches, isOn: Binding(
                get: { controls.showsTouches }, set: { perform(details.showTouchesCommand($0)) }))
                .disabled(!controls.behaviourIsEnabled)
            Divider()
            Button(Wording.gestureTester) { GestureTesterWindow.open(details.id, perform: perform) }
                .disabled(controls.gestureTester != .available)
            if let reason = controls.gestureTester.reason {
                Text(Wording.gestureTesterUnavailable(reason))
            }
            switch controls.setUp {
            case .calibrateAndTest(let availability):
                Button(Wording.calibrateCorners) { perform(details.calibrateCommand) }
                    .disabled(availability != .available)
                Button(Wording.test) { perform(details.testCommand) }
                    .disabled(availability != .available)
                if let reason = availability.reason {
                    Text(Wording.setUpUnavailable(reason))
                }
            case .setUpTouchscreens(let availability):
                Button(Wording.setUpTouchscreens) { perform(MenuTouchscreenDetails.setUpCommand) }
                    .disabled(availability != .available)
                if let reason = availability.reason {
                    Text(Wording.setUpUnavailable(reason))
                }
            }
        }
        if let support = details.support?.whileFinishing(SupportChecksFinishing.shared.isFinishing(details.id)),
           let target = details.supportTarget {
            Divider()
            Button(Wording.helpMeSupport) { SupportCheckWindow.open(target, perform: perform) }
                .disabled(support != .available)
            if support != .available {
                Text(Wording.supportUnavailable(support))
            }
        }
        Divider()
        Button(Wording.settingsFor(name: details.name)) { openSettings(details.pane) }
    }
}
