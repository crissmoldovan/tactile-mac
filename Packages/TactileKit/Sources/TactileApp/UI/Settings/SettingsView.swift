import SwiftUI

/// The Settings window: touchscreens in a sidebar, connected first with a status dot each and the
/// remembered ones greyed, then General; the selected one's pane beside it.
///
/// It reads `model.steadySnapshot` (the snapshot without the gesture tester's feed, which it never
/// shows, so a gesture in the tester doesn't draw it again) and sends `model.perform`, nothing else.
/// Its only state of its own is which pane is selected, and whether the person chose it.
public struct SettingsView<Model: AppModel>: View {
    private let model: Model
    /// The pane shown, and highlighted in the sidebar.
    @State private var selection: SidebarItem?
    /// Whether the person has chosen a pane. Until then Settings follows what needs them.
    @State private var chosenByPerson: Bool
    /// Bumped to redraw the sidebar's highlight after a click in its empty space cleared it.
    @State private var highlightRefresh = 0
    /// A pane asked for from the menu (Settings for <name>…).
    private let paneRequests = SettingsPaneRequests.shared
    /// General's touch devices Tactile doesn't list: the app's; nil in previews, which watch nothing.
    private let notListed: NotListedDevices?

    /// The app's Settings, whose General lists the touch devices Tactile doesn't.
    public init(model: Model) {
        self.init(model: model, selection: nil, notListed: model is TactileModel ? NotListedDevices.shared : nil)
    }

    init(model: Model, selection: SidebarItem?, notListed: NotListedDevices? = nil) {
        self.notListed = notListed
        self.model = model
        _selection = State(initialValue: selection)
        _chosenByPerson = State(initialValue: selection != nil)
    }

    /// Wide enough for the desk's longest display label in the Display pop-up, with the sidebar.
    static var minimumSize: CGSize { CGSize(width: 800, height: 540) }

    public var body: some View {
        let snapshot = model.steadySnapshot
        let shown = SidebarItem.resolve(selection, in: snapshot)
        let _ = highlightRefresh
        NavigationSplitView {
            SettingsSidebar(snapshot: snapshot, selection: Binding(
                get: { selection },
                set: { picked in
                    guard let picked else {
                        // A click in empty space cleared the list's selection: keep the pane shown,
                        // and highlight it again.
                        selection = SidebarItem.resolve(nil, previous: selection, in: model.snapshot)
                        highlightRefresh &+= 1
                        return
                    }
                    selection = picked
                    chosenByPerson = true
                }))
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            SettingsDetail(snapshot: snapshot, item: shown, perform: { model.perform($0) },
                           snapshotNow: { model.snapshot }, notListed: notListed)
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .background(SettingsWindowReader())
        .onAppear {
            if selection == nil {
                selection = SidebarItem.initial(for: snapshot)
            }
        }
        .onChange(of: paneRequests.count, initial: true) {
            if let pane = paneRequests.take() {
                selection = pane
                chosenByPerson = true
            }
        }
        .onChange(of: snapshot) {
            let next = SidebarItem.following(selection, chosenByPerson: chosenByPerson, in: model.snapshot)
            if next != selection {
                selection = next
            }
        }
    }
}

/// The sidebar list.
struct SettingsSidebar: View {
    var snapshot: AppSnapshot
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section(Wording.touchscreens) {
                ForEach(snapshot.touchscreens) { touchscreen in
                    SidebarTouchscreenRow(touchscreen: touchscreen)
                        .tag(SidebarItem.touchscreen(touchscreen.id))
                }
                if snapshot.touchscreens.isEmpty {
                    Text(Wording.noTouchscreens)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                SidebarGeneralRow()
                    .badge(snapshot.warnings.count)
                    .tag(SidebarItem.general)
            }
        }
        .listStyle(.sidebar)
    }
}

/// A touchscreen in the sidebar: its dot and its name, greyed when it isn't connected.
struct SidebarTouchscreenRow: View {
    var touchscreen: TouchscreenSnapshot

    var body: some View {
        Label {
            Text(touchscreen.name)
                .lineLimit(1)
                .foregroundStyle(touchscreen.isConnected ? .primary : .secondary)
        } icon: {
            StatusDot(indicator: StatusIndicator(touchscreen))
        }
        .accessibilityValue(Wording.menuState(for: touchscreen))
    }
}

struct SidebarGeneralRow: View {
    var body: some View {
        Label(Wording.general, systemImage: "gearshape")
    }
}

/// The pane for what the sidebar has selected.
struct SettingsDetail: View {
    var snapshot: AppSnapshot
    var item: SidebarItem
    var perform: PerformCommand
    /// The model's snapshot as it is when called (see `TouchscreenPane.snapshotNow`).
    var snapshotNow: (@MainActor () -> AppSnapshot)? = nil
    /// General's touch devices Tactile doesn't list; nil where nothing is watched.
    var notListed: NotListedDevices? = nil

    var body: some View {
        switch item {
        case .general:
            GeneralPane(snapshot: snapshot, perform: perform, notListed: notListed)
        case .touchscreen(let id):
            if let touchscreen = snapshot.touchscreens.first(where: { $0.id == id }) {
                TouchscreenPane(touchscreen: touchscreen, snapshot: snapshot, perform: perform, snapshotNow: snapshotNow)
                    .id(id)
            } else {
                GeneralPane(snapshot: snapshot, perform: perform, notListed: notListed)
            }
        }
    }
}
