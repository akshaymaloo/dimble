// ItemMenuActions.swift
// What a tile's right-click menu offers and does, in one place: the panel's
// menu and the layout editor's both read it. Each keeps what is its own (the
// panel closes itself first and moves an icon at once, the editor draws the
// move and waits for Apply).

import AppKit
import PelmetCore
import PelmetEngine

@MainActor
enum ItemMenuActions {
    static var openMenuTitle: String { String(localized: "Open Menu") }
    static var showInBarTitle: String { String(localized: "Show in Menu Bar") }

    static func quitTitle(_ appName: String) -> String { String(localized: "Quit \(appName)") }

    static func moveTitle(_ section: PelmetCore.Section) -> String {
        switch section {
        case .visible: String(localized: "Move to Visible")
        case .hidden: String(localized: "Move to Hidden")
        case .alwaysHidden: String(localized: "Move to Always Hidden")
        }
    }

    /// The sections an icon can go to from where it is, in menu order. None
    /// for the clock and Control Center, which macOS pins in place.
    static func moveTargets(of key: ItemID, appState: AppState) -> [PelmetCore.Section] {
        guard !appState.isImmovable(key) else { return [] }
        let current = appState.settings.sectionModel.section(of: key)
        return [.visible, .hidden, .alwaysHidden].filter { $0 != current }
    }

    /// Show in Menu Bar. `source` names the surface in the log.
    static func showInBar(_ key: ItemID, appState: AppState, source: String) {
        PelmetLog.log("\(source): show \(key.rawValue) in the bar")
        appState.showItemInBar(key)
    }

    /// An app the person installed: Open and Quit mean something for it.
    /// Apple's hosts (Control Center, the clock) and Pelmet's own items are not.
    static func isThirdParty(_ bundle: String) -> Bool {
        !bundle.hasPrefix("com.apple.") && !PelmetBundle.ownIDs.contains(bundle)
    }

    /// The app behind an icon, when Quit applies to it. `title` is what the
    /// icon is called when its app has no name of its own.
    static func app(for item: ObservedItem, title: String) -> (bundleID: String, name: String)? {
        guard let bundle = item.id.bundleID, isThirdParty(bundle) else { return nil }
        let name = item.appName ?? ItemNaming.appName(forBundle: bundle)
        return (bundle, name ?? title)
    }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func quit(_ bundleID: String, source: String) {
        PelmetLog.log("\(source): quit \(bundleID)")
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            running.terminate()
        }
    }
}
