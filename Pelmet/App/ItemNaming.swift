// ItemNaming.swift
// What a menu bar item is called, for people. One home for it: the layout
// editor's tiles and the command bar's rows both ask here, so an icon never
// has two names. Never the agent's placeholder title ("Item-0"): the app's
// name stands in, then the last piece of its bundle id.

import AppKit
import PelmetCore
import PelmetEngine

enum ItemNaming {
    static func displayName(for item: ObservedItem) -> String {
        displayName(for: item.id, appName: item.appName)
    }

    /// `appName` is the owning app's name when the caller has one (a live
    /// item carries it, a concealed stand-in is given it); without it the
    /// bundle is looked up.
    static func displayName(for id: ItemID, appName: String? = nil) -> String {
        if id.bundleID == PelmetBundle.textInputAgentID {
            return InputSourcePresentation.shared.name
        }
        // Pelmet's own items: name the thing, not the app that hosts it.
        switch id.pelmetItem {
        case .separator: return String(localized: "Separator")
        case .mediaControls: return String(localized: "Media")
        case .cameraMic: return String(localized: "Camera")
        case .airdrop: return String(localized: "AirDrop")
        case .timer: return String(localized: "Timer")
        case .userSwitching: return String(localized: "Users")
        case .shortcutsMenu: return String(localized: "Shortcuts")
        case .timeMachine: return String(localized: "Time Machine")
        case .siri: return String(localized: "Siri")
        case .focus: return String(localized: "Focus")
        case .quickNote: return String(localized: "Quick Note")
        case .liveActivity: return String(localized: "Live Activities")
        default: break
        }
        // SystemUIServer's extras enumerate as one item titled with every
        // extra it shows ("Siri, TimeMachine"): name each, comma-joined.
        if id.bundleID == PelmetBundle.systemUIServerID,
           case .status(_, let title) = id.parsed {
            let names = title.components(separatedBy: ", ").map { extra -> String in
                switch extra {
                case "TimeMachine": String(localized: "Time Machine")
                case "Item-0": String(localized: "System")
                default: extra
                }
            }
            return names.joined(separator: ", ")
        }
        if MenuBarPolicy.systemItem(for: id) == .primaryBentoBox {
            return String(localized: "Control Center")
        }
        if id.rawValue.contains("::com.apple.menuextra.") {
            let suffix = id.rawValue.components(separatedBy: ".").last ?? String(localized: "System")
            // The one brand name capitalising the suffix gets wrong.
            if suffix == "wifi" { return "Wi-Fi" }
            return suffix.replacingOccurrences(of: "-", with: " ").capitalized
        }
        // Apple's login-item extras are named after their executable
        // ("PasswordsMenuBarExtra", "WeatherMenu"); the tile says what the
        // icon is: the app that ships it.
        if let bundle = id.bundleID, MenuBarPolicy.isBundleHideableAppleHost(bundle),
           let shipping = shippingApp(for: bundle)?.name {
            return shipping
        }
        if let name = usableAppName(appName, bundle: id.bundleID) {
            return name
        }
        return id.bundleID?.components(separatedBy: ".").last ?? "?"
    }

    /// The owning app's name for people: `given` (what a live item carries)
    /// when it says something, else the bundle's own, else, for a helper
    /// named after its bundle id (Fantastical's
    /// "85C27NK92C.com.flexibits.fantastical2.mac.helper", #81), the app it
    /// ships inside. The command bar's subtitles use it too, so neither says
    /// a bundle id.
    static func usableAppName(_ given: String?, bundle: String?) -> String? {
        usable(given) ?? bundle.flatMap { appName(forBundle: $0) ?? shippingApp(for: $0)?.name }
    }

    /// What the process behind a bundle calls itself, never the app it
    /// ships inside: `given` (a live item's own), its running name, its
    /// bundle's display name. Quit ends that process, so Quit says this.
    static func ownName(_ given: String?, bundle: String) -> String? {
        if let name = usable(given) ?? appName(forBundle: bundle) { return name }
        // Running under a name that is its bundle id: its bundle's own name.
        guard let url = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.bundleURL
        else { return nil }
        return usable(FileManager.default.displayName(atPath: url.path))
    }

    /// The app a helper ships inside when that is whose name
    /// `usableAppName` gives it (the helper has none of its own). Nil
    /// otherwise.
    static func parentApp(_ given: String?, bundle: String) -> ShippingApp? {
        guard usable(given) == nil, appName(forBundle: bundle) == nil else { return nil }
        return shippingApp(for: bundle)
    }

    /// The app's own name for a bundle: the running copy's, else the
    /// installed bundle's as Finder shows it. Cached, a miss too until an
    /// app launches (one LaunchServices query each, and the board and the
    /// command bar ask per item).
    static func appName(forBundle bundle: String) -> String? {
        if let cached = appNames[bundle] { return cached }
        if appNameMisses.contains(bundle) { return nil }
        var name = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.localizedName
        if name == nil, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            name = FileManager.default.displayName(atPath: url.path)
        }
        name = usable(name)
        if let name {
            appNames[bundle] = name
        } else {
            appNameMisses.insert(bundle)
            watchLaunches()
        }
        return name
    }

    private static var appNames: [String: String] = [:]

    /// A name that says something: not empty, not the agent's "Item-N", not
    /// a bundle id standing in for one (no spaces, two dots or more).
    private static func usable(_ name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        if name.hasPrefix("Item-"), Int(name.dropFirst("Item-".count)) != nil { return nil }
        if !name.contains(where: \.isWhitespace), name.filter({ $0 == "." }).count >= 2 { return nil }
        return name
    }

    /// The app a login-item extra ships inside: Finder's localized name for
    /// it and its bundle id (what Open launches for the helper's icon).
    struct ShippingApp {
        let name: String
        let bundleID: String?
    }

    /// …/Weather.app/Contents/Library/LoginItems/WeatherMenu.app → Weather.
    /// nil for a host that is its own app or that can't be found. One
    /// LaunchServices lookup per bundle, then cached, a miss too: the board
    /// asks on every tile render. A launch clears the misses, since a helper
    /// that wasn't running or registered may be now (a nil kept for good once
    /// named one by its bundle id until relaunch).
    private static var shippingApps: [String: ShippingApp?] = [:]
    private static func shippingApp(for bundle: String) -> ShippingApp? {
        if let cached = shippingApps[bundle] { return cached }
        var app: ShippingApp?
        // The running copy first: a third-party helper LaunchServices may not
        // have registered is still on the bar.
        if let url = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            let parts = url.pathComponents
            // <App>.app / Contents / Library / LoginItems / <Extra>.app
            if parts.count >= 5, parts[parts.count - 2] == "LoginItems", parts[parts.count - 3] == "Library",
               parts[parts.count - 4] == "Contents", parts[parts.count - 5].hasSuffix(".app") {
                let parent = url.deletingLastPathComponent().deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                app = ShippingApp(
                    name: FileManager.default.displayName(atPath: parent.path),
                    bundleID: Bundle(url: parent)?.bundleIdentifier
                )
            }
        }
        shippingApps[bundle] = app
        if app == nil { watchLaunches() }
        return app
    }

    /// Bundles `appName(forBundle:)` found no name for.
    private static var appNameMisses: Set<String> = []
    private static var launchObserver: (any NSObjectProtocol)?

    /// Any app launching clears the misses: a bundle neither running nor
    /// installed cost two running-app and two LaunchServices lookups on every
    /// tile render while they weren't kept.
    private static func watchLaunches() {
        guard launchObserver == nil else { return }
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ItemNaming.forgetMisses() }
        }
    }

    private static func forgetMisses() {
        appNameMisses.removeAll()
        shippingApps = shippingApps.filter { $0.value != nil }
    }
}
