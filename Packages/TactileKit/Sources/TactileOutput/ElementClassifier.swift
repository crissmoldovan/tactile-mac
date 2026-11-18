import TactileGestures

/// Decides whether one finger should drag or scroll, from the Accessibility roles under it.
public enum ElementClassifier {

    /// Things one finger grabs rather than scrolls past.
    static let draggable: Set<String> = [
        "AXImage",  // icons on the desktop and in Finder's icon view
        "AXSlider", "AXScrollBar", "AXValueIndicator", "AXSplitter", "AXIncrementor",
        "AXWindow",  // the window's own frame, which is its title bar
    ]

    /// Containers whose content one finger scrolls.
    static let scrollable: Set<String> = [
        "AXScrollArea", "AXWebArea", "AXList", "AXTable", "AXOutline", "AXBrowser", "AXTextArea",
    ]

    /// - Parameters:
    ///   - roles: the element under the finger first, then its ancestors.
    ///   - hasSelectedText: whether the element under the finger has text selected.
    public static func intent(roles: [String], hasSelectedText: Bool) -> OneFingerIntent {
        guard let own = roles.first else { return .drag }
        if hasSelectedText { return .drag }
        if roles.contains("AXWebArea") { return .scroll }  // web pages scroll even over images and links
        if draggable.contains(own) { return .drag }
        if roles.contains(where: scrollable.contains) { return .scroll }
        return .drag  // canvases and anything unrecognised
    }

    /// - Parameters:
    ///   - roles: the element under the finger first, then its ancestors.
    ///   - hasSelectedText: whether the element under the finger has text selected.
    ///   - completed: whether the walk up the element tree and the selected-text check both
    ///     finished in time. A partial answer is never classified: if not, the answer is drag.
    public static func intent(roles: [String], hasSelectedText: Bool, completed: Bool) -> OneFingerIntent {
        guard completed else { return .drag }  // no answer in time: drag
        return intent(roles: roles, hasSelectedText: hasSelectedText)
    }
}
