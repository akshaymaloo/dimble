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
    /// The icon's row in Settings › Search (the row has its alias too), and
    /// the command bar's ⌘K line that records one in place, named for the
    /// shortcut it holds.
    static func shortcutTitle(_ id: ItemID, appState: AppState) -> String {
        appState.settings.itemHotkeys[id.sectionKey.rawValue] == nil
            ? String(localized: "Add a Shortcut…") : String(localized: "Change Shortcut…")
    }

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

    /// Whether Search can alias this icon: every one it lists, which leaves
    /// out Pelmet's separators and chevron.
    static func canAlias(_ id: ItemID) -> Bool {
        !id.isPelmetSeparator && !id.isPelmetChevron
    }

    /// Add a Shortcut…: Settings › Search with the icon's row in view.
    /// `source` names the surface in the log.
    static func editShortcut(_ key: ItemID, appState: AppState, source: String) {
        PelmetLog.log("\(source): shortcut for \(key.rawValue)")
        appState.openShortcut(for: key)
    }

    /// An app the person installed: Open and Quit mean something for it.
    /// Apple's hosts (Control Center, the clock) and Pelmet's own items are not.
    static func isThirdParty(_ bundle: String) -> Bool {
        !bundle.hasPrefix("com.apple.") && !PelmetBundle.ownIDs.contains(bundle)
    }

    /// An icon's app as Open and Quit offer it, each label naming what its
    /// action acts on. A login-item helper that owns an icon (Fantastical's)
    /// is named for its parent on the tile; Quit still ends the helper, so it
    /// says the helper's own name, and Open launches the parent.
    struct ItemApp {
        /// The process that owns the icon: what Quit ends and names.
        let bundleID: String
        let name: String
        /// What Open launches and names: the app the owner ships inside when
        /// the icon is named for it, else the owner.
        let openBundleID: String
        let openName: String
    }

    /// The app behind an icon, when Open and Quit apply to it. Every menu
    /// that offers them reads this (the command bar's ⌘K, the panel's and
    /// the editor's right-click), so the labels and the targets agree.
    static func app(for item: ObservedItem) -> ItemApp? {
        guard let bundle = item.id.bundleID, isThirdParty(bundle) else { return nil }
        let name = ItemNaming.ownName(item.appName, bundle: bundle) ?? bundle.components(separatedBy: ".").last ?? bundle
        if let parent = ItemNaming.parentApp(item.appName, bundle: bundle), let parentID = parent.bundleID {
            return ItemApp(bundleID: bundle, name: name, openBundleID: parentID, openName: parent.name)
        }
        return ItemApp(bundleID: bundle, name: name, openBundleID: bundle, openName: name)
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
