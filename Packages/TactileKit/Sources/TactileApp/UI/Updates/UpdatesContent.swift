// What the menu, the update window and General show about updates, worked out from the updater's
// state alone: pure, so every state is tested without a window.

import Foundation
import TactileUpdates

/// The updater's rows in the menu-bar panel.
struct UpdateMenuContent: Equatable {
    /// "Update to 0.6.0…", shown prominently while a newer version is known, until it installs.
    var updateTitle: String?
    /// Whether Check for Updates… can be chosen: not while a manual check, a download or an install
    /// is under way. Chosen during an automatic check, it makes that check a manual one.
    var canCheck: Bool
    /// The line beneath Check for Updates…: what is under way, or what the last manual check or
    /// install left to say. An automatic check shows nothing.
    var line: String?

    init(_ state: UpdateState) {
        switch state.phase {
        case .installing: updateTitle = nil
        default: updateTitle = state.available.map { Wording.updateTo($0.version.description) }
        }
        canCheck = state.phase == .idle || state.phase == .checking(manual: false)
        line = Self.line(state)
    }

    init(updateTitle: String?, canCheck: Bool, line: String?) {
        self.updateTitle = updateTitle
        self.canCheck = canCheck
        self.line = line
    }

    /// A build that doesn't update itself: Check for Updates… can't be chosen, and beneath it, why.
    static let off = UpdateMenuContent(updateTitle: nil, canCheck: false, line: Wording.updatesOff)

    static func line(_ state: UpdateState) -> String? {
        switch state.phase {
        case .checking(manual: true): return Wording.checkingForUpdates
        case .checking(manual: false): return nil
        case .downloading(let offer): return Wording.downloadingUpdate(offer.version.description)
        case .verifying(let offer): return Wording.verifyingUpdate(offer.version.description)
        case .installing(let offer): return Wording.installingUpdate(offer.version.description)
        case .idle: return state.notice.map { notice(notice: $0, state) }
        }
    }

    static func notice(notice: UpdateNotice, _ state: UpdateState) -> String {
        switch notice {
        case .upToDate:
            return Wording.newestVersion(state.runningVersion)
        case .needsNewerSystem(let offer):
            return Wording.needsNewerMacOS(version: offer.version.description,
                                           minimum: offer.minimumSystemVersion.description)
        case .checkFailed(let failure), .installFailed(let failure):
            return Wording.updateFailure(failure, site: state.siteHost)
        }
    }
}

/// The update window: what it says, and its buttons.
struct UpdateWindowContent: Equatable {
    enum Action: Equatable {
        case install
        case later
        case cancel
        case ok

        var title: String {
            switch self {
            case .install: return Wording.installAndRelaunch
            case .later: return Wording.later
            case .cancel: return Wording.cancel
            case .ok: return Wording.ok
            }
        }
    }

    var title: String
    var subtitle: String?
    /// The release notes, a paragraph each.
    var notes: [String] = []
    /// What is under way, or what went wrong.
    var line: String?
    var lineIsProblem = false
    var isBusy = false
    /// The default button, on the right.
    var primary: Action?
    var primaryIsEnabled = true
    /// The other button, on its left.
    var secondary: Action?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    init(_ state: UpdateState) {
        switch state.phase {
        case .checking(manual: true):
            self.init(title: Wording.checkingForUpdates)
            isBusy = true
            secondary = .cancel
        case .downloading(let offer), .verifying(let offer):
            self.init(offer: offer, state: state)
            line = UpdateMenuContent.line(state)
            isBusy = true
            primaryIsEnabled = false
            secondary = .cancel
        case .installing(let offer):
            self.init(offer: offer, state: state)
            line = Wording.installingUpdate(offer.version.description) + " " + Wording.relaunchesInAMoment
            isBusy = true
            primaryIsEnabled = false
            secondary = nil
        case .idle, .checking(manual: false):
            self.init(idle: state)
        }
    }

    /// Nothing under way: the last notice, or the newer version, or that this one is the newest.
    private init(idle state: UpdateState) {
        switch state.notice {
        case .upToDate:
            self.init(title: Wording.newestVersion(state.runningVersion))
            primary = .ok
        case .needsNewerSystem(let offer):
            self.init(offer: offer, state: state)
            line = UpdateMenuContent.notice(notice: .needsNewerSystem(offer), state)
            primary = .ok
            secondary = nil
        case .checkFailed(let failure):
            self.init(title: Wording.couldntCheck)
            line = Wording.updateFailure(failure, site: state.siteHost)
            lineIsProblem = true
            primary = .ok
        case .installFailed(let failure):
            if let offer = state.available {
                self.init(offer: offer, state: state)
            } else {
                self.init(title: Wording.newestVersion(state.runningVersion))
                primary = .ok
            }
            line = Wording.updateFailure(failure, site: state.siteHost)
            lineIsProblem = true
        case nil:
            if let offer = state.available {
                self.init(offer: offer, state: state)
            } else {
                self.init(title: Wording.newestVersion(state.runningVersion))
                primary = .ok
            }
        }
        // During an automatic check nothing can be installed until it ends.
        if state.phase != .idle, primary == .install {
            primaryIsEnabled = false
        }
    }

    /// A newer version: its title, the version running, its notes; Later and Install and Relaunch.
    private init(offer: UpdateOffer, state: UpdateState) {
        self.init(title: Wording.updateAvailable(offer.version.description), subtitle: Wording.youHave(state.runningVersion))
        notes = offer.paragraphs
        primary = .install
        secondary = .later
    }

    /// Whether closing the window puts the notice away, as Later and OK do. While something is under
    /// way, closing stops nothing: the check or the download goes on, and the menu shows it.
    var closingDismisses: Bool { !isBusy }
}

/// General's Updates group: the switch, when the last check was, and its button.
struct UpdatesSettingsContent: Equatable {
    var checksAutomatically: Bool
    var explanation: String
    var lastChecked: String
    /// "Check for Updates…", or "Update to 0.6.0…" while a newer version is known.
    var buttonTitle: String
    /// Whether the button opens the newer version's window rather than checking.
    var buttonOpensUpdate: Bool
    var buttonIsEnabled: Bool
    /// What is under way, or the last manual check's or install's word.
    var line: String?

    init(_ state: UpdateState, locale: Locale = .current, timeZone: TimeZone = .current) {
        let menu = UpdateMenuContent(state)
        checksAutomatically = state.checksAutomatically
        explanation = Wording.checkAutomaticallyExplanation(site: state.siteHost)
        lastChecked = Wording.lastChecked(state.lastChecked, locale: locale, timeZone: timeZone)
        buttonOpensUpdate = menu.updateTitle != nil
        buttonTitle = menu.updateTitle ?? Wording.checkForUpdates
        buttonIsEnabled = buttonOpensUpdate || menu.canCheck
        line = menu.line
    }
}
