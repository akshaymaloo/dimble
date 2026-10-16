// BundleRelocation.swift
// Sparkle installs updates under the pre-update filename, so users who update
// from an older name end up with the new app inside the old bundle: Nook.app
// (the nook era), Pelmet.app (up to 0.3.1) or Pliss.app (the 0.3.2 betas,
// before the app became Dimble). The very first thing a mis-named bundle does
// — before migration, before any TCC interaction — is rename itself to
// Dimble.app in the same folder and relaunch from the final path.
//
// The rename keeps permissions: TCC keys a grant on the bundle ID and code
// signature, not the filename. A Finder rename of Pelmet.app to Pliss.app with
// the same bundle ID kept Accessibility and Screen Recording (axTrusted=true,
// checked 2026-10-14). The old worry that a rename invalidates the grant came
// from the nook → Pelmet bundle-ID change, which made a different bundle.
//
// The login item is the one thing that remembers the path: the instance that
// moves the bundle leaves a marker, and the relaunched one registers the login
// item again at the final path (when launch at login is on).

import AppKit
import PelmetCore
import PelmetEngine
import ServiceManagement

enum BundleRelocation {
    /// What the bundle is called once relocated.
    static let finalName = "Dimble.app"
    /// Filenames the app has shipped under that Sparkle can leave behind.
    static let formerNames: Set<String> = ["Nook.app", "Pelmet.app", "Pliss.app"]
    /// Set by the instance that renamed the bundle, taken by the one that
    /// runs from the final path.
    private static let loginItemMarker = "pelmet.relocatedReregisterLoginItem"

    /// Where a bundle named like a former name belongs: Dimble.app in the same
    /// folder. Nil when the name is already right or not one of ours.
    static func relocationTarget(for bundleURL: URL) -> URL? {
        guard formerNames.contains(bundleURL.lastPathComponent) else { return nil }
        return bundleURL.deletingLastPathComponent().appendingPathComponent(finalName)
    }

    /// Returns true when the app is relaunching and the caller must not
    /// continue booting.
    static func relocateIfNeeded() -> Bool {
        let url = Bundle.main.bundleURL
        guard let dest = relocationTarget(for: url) else { return false }
        // Never replace or merge into something already there (a second
        // copy, a rename done by hand): run from where we are.
        guard !FileManager.default.fileExists(atPath: dest.path) else { return false }
        UserDefaults.standard.set(true, forKey: loginItemMarker)
        do {
            try FileManager.default.moveItem(at: url, to: dest)
        } catch {
            // Read-only volume, translocation, permissions — run from where
            // we are rather than dying over a filename.
            UserDefaults.standard.removeObject(forKey: loginItemMarker)
            return false
        }
        PelmetLog.log("relocate: \(url.lastPathComponent) renamed to \(finalName), relaunching from \(dest.path)")
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: dest, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }

    /// Called once the app runs from its final path. After a relocation the
    /// login item may still be filed under the old path: drop it and register
    /// it again here, only when the user has launch at login on.
    static func reregisterLoginItemIfRelocated() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: loginItemMarker) else { return }
        defaults.removeObject(forKey: loginItemMarker)
        guard SettingsStore.load().launchAtLogin else { return }
        let service = SMAppService.mainApp
        try? service.unregister()
        do {
            try service.register()
            PelmetLog.log("relocate: login item registered again at \(Bundle.main.bundleURL.path)")
        } catch {
            PelmetLog.log("relocate: login item not registered again at \(Bundle.main.bundleURL.path) — \(error.localizedDescription)")
        }
    }
}
