// Xcode previews of the interface, on the preview desk.

import SwiftUI
import TactileScreens

#Preview("Settings: the desk") {
    SettingsView(model: PreviewModel(.desk))
}

#Preview("Settings: first run") {
    SettingsView(model: PreviewModel(.nothingPaired))
}

#Preview("Settings: every warning") {
    SettingsView(model: PreviewModel(.allWarnings))
}

#Preview("Settings: identical twins") {
    SettingsView(model: PreviewModel(.identicalTwins))
}

#Preview("Menu-bar panel") {
    MenuBarView(model: PreviewModel(.desk))
}

#Preview("A touchscreen's details: the ILITEK") {
    TouchscreenDetailsRoot(
        model: PreviewModel(.desk), id: TouchscreenID(rawValue: "222a:0001:V06.00.00.00"), actions: .none)
}

#Preview("A touchscreen's details: not set up") {
    TouchscreenDetailsRoot(
        model: PreviewModel(.nothingPaired), id: TouchscreenID(rawValue: "222a:0001:V06.00.00.00"), actions: .none)
}

#Preview("Identify: 12.3FHD") {
    IdentifyCard(name: "12.3FHD", detail: "12.3″ · 1600 × 600 · below the main display",
                 screenSize: CGSize(width: 1600, height: 600))
        .frame(width: 800, height: 300)
        .scaleEffect(0.5)
}

#Preview("First-run window") {
    FirstRunView(names: ["ILITEK-TP", "TouchScreen"], setUp: {}, notNow: {})
}

#Preview("Set-up mode, playing by itself") {
    let model = PreviewModel(.nothingPaired)
    model.perform(.beginSetUpMode)
    model.playSetUp()
    return SetUpPreviewDesk(
        model: model, displays: ["Built-in Retina Display", "HDMI", "LG HDR 4K", "12.3FHD"], scale: 0.2)
}

#Preview("Set-up mode on the strip's display") {
    let model = PreviewModel(.desk)
    model.perform(.beginSetUpMode)
    model.playSetUp()
    return SetUpPreviewDesk(model: model, displays: ["12.3FHD"], scale: 0.5)
}

/// The set-up screens of the named displays, side by side and scaled down, following the model:
/// the backdrop as drawn, and the buttons where the overlay would put them, clickable.
struct SetUpPreviewDesk: View {
    var model: PreviewModel
    var displays: [String]
    var scale: CGFloat

    var body: some View {
        let snapshot = model.snapshot
        let plan = SetUpScreens.plan(snapshot)
        HStack(alignment: .top, spacing: 16) {
            ForEach(displays, id: \.self) { name in
                if let display = snapshot.displays.first(where: { $0.name == name }),
                    let screen = plan.first(where: { $0.displayID == display.id })
                {
                    let size = display.frame.size
                    ZStack(alignment: .topLeading) {
                        Color.gray
                        SetUpBackdrop(screen: screen, displaySize: size)
                        if screen.hasControls {
                            SetUpControls(
                                screen: screen, displaySize: size, perform: { model.perform($0) },
                                check: { id in
                                    // Leaves set-up mode; the preview opens no check, which reads devices.
                                    SetUpSupportCheck.leaveThenCheck(
                                        id, perform: { model.perform($0) }, snapshot: { model.snapshot }, open: { _ in })
                                })
                                .frame(width: size.width, height: size.height, alignment: alignment(screen.placement))
                                .offset(y: offset(screen.placement, height: size.height))
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
                    .clipped()
                }
            }
        }
        .padding(16)
    }

    private func offset(_ placement: SetUpControlsPlacement, height: CGFloat) -> CGFloat {
        switch placement {
        case .belowCentre: return height / 2 + SetUpScreens.controlsGap
        case .centre: return 0
        case .bottom: return -SetUpScreens.bottomMargin
        }
    }

    private func alignment(_ placement: SetUpControlsPlacement) -> Alignment {
        switch placement {
        case .belowCentre: return .top
        case .centre: return .center
        case .bottom: return .bottom
        }
    }
}
