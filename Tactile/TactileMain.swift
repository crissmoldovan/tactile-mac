//
//  TactileMain.swift
//  Tactile
//
//  The entry point. Everything else is in the TactileKit package: the delegate builds the app
//  (`TactileAppDelegate`), and the scenes are the menu-bar item and the Settings window.
//

import SwiftUI
import TactileApp

@main
struct TactileMain: App {
    @NSApplicationDelegateAdaptor(TactileAppDelegate.self) private var delegate

    var body: some Scene {
        TactileScenes(model: delegate.model)
    }
}
