// QuickNote.swift
// Pelmet's own Quick Note item. Apple's icon is Notes' Control Center
// control (`QuickNoteControl`, in its widget extension), and macOS takes
// every Control off the bar while the hide assertion is held, whatever the
// allowlist names (#99). The control has no verb to call, but Quick Note
// has a keyboard shortcut, and a click can post it: symbolic hotkey 190 in
// `com.apple.symbolichotkeys`, [character, keyCode, modifiers] — fn+Q by
// default, [113, 12, 0x800000] (probed 2026-10-23, 27.2; the modifier bits
// are CGEventFlags' own). A keyDown with those flags, then a keyUp with
// none, ~30ms apart at the HID tap opened a Quick Note window.
//
// A shortcut the user switched off, or one the table won't give up, posts
// nothing: the chord would type into the frontmost app. Notes opens instead.

import AppKit
import PelmetEngine

enum QuickNote {
    /// What a click does, read from the shortcut table.
    enum Plan: Equatable {
        case post(keyCode: CGKeyCode, flags: CGEventFlags)
        /// Nothing safe to post: open Notes, and say why in the log.
        case openNotes(reason: String)
    }

    /// Hotkey 190 is Quick Note; with no entry the Mac is on its default.
    private static let hotKeyID = "190"
    private static let defaultPlan = Plan.post(keyCode: 12 /* Q */, flags: .maskSecondaryFn)
    private static let modifiers: CGEventFlags = [
        .maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn,
    ]
    /// The table's "no key" key code (65535): a combo with nothing to post.
    private static let noKey = 0xFFFF

    /// Runs the user's Quick Note shortcut, else opens Notes.
    static func open() {
        let table = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys")
        // Without Accessibility the HID tap drops posted keys without a word.
        let plan = AXIsProcessTrusted() ? plan(from: table) : .openNotes(reason: "no Accessibility to post the shortcut")
        switch plan {
        case .post(let keyCode, let flags):
            PelmetLog.log("quick note: posting keyCode \(keyCode) flags 0x\(String(flags.rawValue, radix: 16))")
            post(keyCode: keyCode, flags: flags)
        case .openNotes(let reason):
            PelmetLog.log("quick note: \(reason), opening Notes")
            openNotes()
        }
    }

    /// The decision, apart from the posting. `table` is `AppleSymbolicHotKeys`.
    static func plan(from table: [String: Any]?) -> Plan {
        guard let raw = table?[hotKeyID] else { return defaultPlan }
        guard let entry = raw as? [String: Any],
              let enabled = (entry["enabled"] as? NSNumber)?.boolValue else {
            return .openNotes(reason: "shortcut entry unreadable")
        }
        guard enabled else { return .openNotes(reason: "shortcut is off in Keyboard Shortcuts") }
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Any], parameters.count >= 3,
              let keyCode = (parameters[1] as? NSNumber)?.intValue,
              let mask = (parameters[2] as? NSNumber)?.uint64Value,
              (0..<noKey).contains(keyCode) else {
            return .openNotes(reason: "shortcut parameters unreadable")
        }
        return .post(keyCode: CGKeyCode(keyCode), flags: CGEventFlags(rawValue: mask).intersection(modifiers))
    }

    private static func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            let up = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState), virtualKey: keyCode, keyDown: false)
            // No flags, so no modifier is left held after the chord.
            up?.flags = []
            up?.post(tap: .cghidEventTap)
        }
    }

    private static func openNotes() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") else {
            PelmetLog.log("quick note: Notes not found")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { PelmetLog.log("quick note: Notes failed to open — \(error.localizedDescription)") }
        }
    }
}
