// ShortcutRecorder.swift
// Click-to-record global shortcut. A local keyDown monitor inside our own
// settings window, so recording needs no extra permission. ⎋ cancels,
// ⌫ turns the shortcut off (#79), and the ↺ inside the chip
// always brings `fallback` back (⌫ once left no way back, 2026-09-15).
// It listens only to its own window and only until the person moves on: a
// click anywhere but the chip, the window losing key or another recorder
// starting ends it (it once kept every key app-wide, so ⌫ in the alias field
// removed an icon's shortcut and ⌘A became one).

import Carbon.HIToolbox
import PelmetCore
import PelmetEngine
import SwiftUI

struct ShortcutRecorder: View {
    @Binding var shortcut: HotkeySpec?
    /// What the restore button brings back. Nil: there is no default (an
    /// icon's own shortcut), so ⌫ and × remove it instead of turning it off.
    let fallback: HotkeySpec?
    /// Takes the recorded shortcut itself and says whether it was kept; a
    /// refusal beeps and keeps listening (the caller shows why). Without
    /// it, the shortcut goes straight into the binding.
    var accept: ((HotkeySpec?) -> Bool)? = nil
    @State private var recording = false
    @State private var hovering = false
    /// The key and click monitors and the window and recorder observers,
    /// while recording.
    @State private var monitors: [Any] = []
    @State private var observers: [any NSObjectProtocol] = []
    /// The chip's AppKit view, for telling a click on the chip from one
    /// beside it.
    @State private var chipProbe = ChipProbe()
    /// Recorders listening for a shortcut now: the hover panel's typing tap
    /// leaves their keys alone (`HoverTypingTap`).
    private(set) static var listening = 0

    /// Posted when a recorder starts, so one still listening lets go.
    private static let didStartRecording = Notification.Name("app.fif7y.Pelmet.shortcutRecorder.started")

    private var isOff: Bool { shortcut?.isOff == true }

    var body: some View {
        // Both glyphs sit inside the chip's spare width, mirrored: the row
        // never changes size, so nothing moves and the settings rows'
        // ViewThatFits never re-lays mid-click (#54). A restore button
        // beside the chip shifted it left on every custom shortcut, and its
        // exit animation left the chip offset (Gab, 2026-10-07).
        chip
            .background(ChipProbeView(probe: chipProbe))
            // A custom or turned-off shortcut gets a way back to the default
            // without knowing about ⌫ — only while there is something to undo.
            .overlay(alignment: .leading) {
                if !recording, let fallback, let shortcut, shortcut != fallback {
                    glyph("arrow.counterclockwise.circle.fill", help: "Restore \(fallback.display)") {
                        commit(fallback)
                    }
                    .padding(.leading, 6)
                }
            }
            // Turning a shortcut off, only under the pointer: a clash with
            // another app's shortcut is rare (#79) and earns no switch.
            .overlay(alignment: .trailing) {
                if hovering, !recording, let shortcut, !shortcut.isOff {
                    glyph("xmark.circle.fill", help: fallback == nil ? "Remove Shortcut" : "Turn Off") { commit(cleared) }
                        .padding(.trailing, 6)
                        .transition(.opacity)
                }
            }
            .onHover { hovering = $0 }
            .animation(.easeInOut(duration: 0.12), value: hovering)
            .onDisappear(perform: stopRecording)
    }

    private func glyph(_ name: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(help)
    }

    private var chip: some View {
        Button {
            recording ? stopRecording() : startRecording()
        } label: {
            // The chip keeps the width of its widest label at rest. A
            // click grew "⌥⌘N" into "Type shortcut…", the row's ViewThatFits
            // flipped to its vertical candidate, and the recorder there was
            // a fresh view with `recording` false again — the click did
            // nothing (#54, Korean, the Notification Center row).
            ZStack {
                Text("Type shortcut…").hidden()
                if recording {
                    Text("Type shortcut…")
                } else if isOff {
                    Text("None").foregroundStyle(.secondary)
                } else if let shortcut {
                    Text(verbatim: shortcut.display)
                } else {
                    Text("Record shortcut")
                }
            }
            .fixedSize()
            // System font, not monospaced: mono shrinks ⇧⌥⌘ to specks. Apple's
            // menus draw modifier glyphs this size with a touch of tracking.
            .font(.system(size: 13, weight: .medium))
            .kerning(1.5)
            .foregroundStyle(recording ? .secondary : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(.primary.opacity(recording ? 0.04 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(PelmetAccent.accent, lineWidth: recording ? 1.5 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help("Click, then press the new shortcut. ⌫ turns it off, ⎋ cancels.")
    }

    private func startRecording() {
        guard !recording else { return }
        // One recorder at a time: posted before this one listens for it.
        NotificationCenter.default.post(name: Self.didStartRecording, object: nil)
        // The window the chip was clicked in; keys for any other (the command
        // bar, the panel) aren't the recorder's.
        guard let window = NSApp.currentEvent?.window ?? NSApp.keyWindow else { return }
        let windowNumber = window.windowNumber
        recording = true
        monitors = [
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // NSEvent is not Sendable — pull the scalars out before hopping
                // into the actor. The monitor already fires on the main thread.
                let keyCode = Int(event.keyCode)
                let flags = event.modifierFlags
                let chars = event.charactersIgnoringModifiers
                let ours = event.windowNumber == windowNumber
                let consumed = MainActor.assumeIsolated {
                    guard ours else {
                        letGo("a key for another window")
                        return false
                    }
                    return handle(keyCode: keyCode, flags: flags, chars: chars)
                }
                return consumed ? nil : event
            },
            // The chip's own click toggles the recording on mouse-up; any
            // other click (a field, another recorder, another window) ends it
            // and goes where it was meant to. Hit-tested, not read from the
            // hover state: that one is stale when the window became key
            // without the pointer moving, and a click on the chip stopped the
            // recording only for its mouse-up to start it again.
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { event in
                let ours = event.windowNumber == windowNumber
                let location = event.locationInWindow
                MainActor.assumeIsolated {
                    let onChip = ours && (chipProbe.contains(location) ?? hovering)
                    if !onChip { letGo("a click outside the chip") }
                }
                return event
            },
        ].compactMap { $0 }
        Self.listening += 1
        observers = [
            NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { letGo("its window resigned key") }
            },
            NotificationCenter.default.addObserver(
                forName: Self.didStartRecording, object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { letGo("another recorder started") }
            },
        ]
    }

    /// Stops a recording the person moved away from, saying why.
    private func letGo(_ reason: String) {
        guard recording else { return }
        PelmetLog.log("settings: shortcut recorder stopped, \(reason)")
        stopRecording()
    }

    /// Every way a recording ends comes here (⎋, a commit, the chip, letting
    /// go, the view leaving), so `listening` stays balanced.
    private func stopRecording() {
        if !monitors.isEmpty { Self.listening -= 1 }
        monitors.forEach(NSEvent.removeMonitor)
        observers.forEach(NotificationCenter.default.removeObserver)
        monitors = []
        observers = []
        recording = false
    }

    /// True when the recorder consumed the event.
    private func handle(keyCode: Int, flags: NSEvent.ModifierFlags, chars: String?) -> Bool {
        switch keyCode {
        case kVK_Escape:
            stopRecording()
            return true
        case kVK_Delete:
            commit(cleared)
            return true
        default:
            break
        }
        let mods = Self.carbonModifiers(from: flags)
        guard !Self.wouldType(keyCode: keyCode, modifiers: mods) else {
            NSSound.beep()
            return true
        }
        commit(HotkeySpec(
            keyCode: UInt32(keyCode),
            modifiers: mods,
            display: Self.symbols(flags) + Self.keyName(keyCode: keyCode, chars: chars)
        ))
        return true
    }

    /// What ⌫ and × leave: off for a shortcut with a default, nothing for one
    /// without.
    private var cleared: HotkeySpec? { fallback == nil ? nil : .off }

    private func commit(_ new: HotkeySpec?) {
        if let accept {
            guard accept(new) else {
                NSSound.beep()
                return
            }
        } else {
            shortcut = new
        }
        stopRecording()
    }

    /// True when the shortcut would hijack typing in every app: a bare key,
    /// or shift alone. The function keys type nothing, so they may stand
    /// alone (#103: F8 for Notification Center beeped).
    static func wouldType(keyCode: Int, modifiers: UInt32) -> Bool {
        modifiers & ~UInt32(shiftKey) == 0 && !functionKeys.contains(keyCode)
    }

    static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    /// AppKit modifier flags → the Carbon mask RegisterEventHotKey wants.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        return mods
    }

    /// Select All, Copy, Paste, Cut, Undo and Redo (⌘A ⌘C ⌘V ⌘X ⌘Z ⇧⌘Z):
    /// as an icon's shortcut one would take that edit from every app. Read
    /// from the key's name in `display` (the Roman layout's), so AZERTY's ⌘A
    /// counts.
    static func isEditChord(_ spec: HotkeySpec) -> Bool {
        let key = String(spec.display.drop { "⌃⌥⇧⌘".contains($0) })
        switch spec.modifiers {
        case UInt32(cmdKey): return ["A", "C", "V", "X", "Z"].contains(key)
        case UInt32(cmdKey | shiftKey): return key == "Z"
        default: return false
        }
    }

    static func symbols(_ flags: NSEvent.ModifierFlags) -> String {
        var out = ""
        if flags.contains(.control) { out += "⌃" }
        if flags.contains(.option) { out += "⌥" }
        if flags.contains(.shift) { out += "⇧" }
        if flags.contains(.command) { out += "⌘" }
        return out
    }

    /// The key's name for display. `chars` is `charactersIgnoringModifiers`,
    /// which follows the ACTIVE input source: recording ⌥A with Korean input
    /// on named the shortcut `⌥ㅁ`, and it stayed that way after switching
    /// back to Roman. The registration is by key code and fired on the A key
    /// the whole time — only the label was wrong. macOS names shortcuts from
    /// the Roman layout, so ask that layout first and keep `chars` as the
    /// fallback for a key it cannot translate.
    static func keyName(
        keyCode: Int,
        chars: String?,
        romanKey: @MainActor (Int) -> String? = romanKeyName
    ) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥",
            kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
            kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
            kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
            kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        ]
        if let name = special[keyCode] { return name }
        if let roman = romanKey(keyCode), !roman.isEmpty { return roman.uppercased() }
        return chars?.uppercased() ?? "?"
    }

    /// What `keyCode` types on the current ASCII-capable layout, unmodified.
    /// Nil when there is no such layout or the key does not produce a
    /// character on it (a dead key, a keypad code some layouts omit).
    static func romanKeyName(keyCode: Int) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String? in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
    }
}

/// The chip's frame as AppKit sees it, for hit-testing a click while the
/// recorder listens.
private final class ChipProbe {
    weak var view: NSView?

    /// Nil when the chip has no view yet.
    func contains(_ locationInWindow: NSPoint) -> Bool? {
        guard let view, view.window != nil else { return nil }
        return view.bounds.contains(view.convert(locationInWindow, from: nil))
    }
}

/// An empty view the size of the chip that clicks pass through.
private struct ChipProbeView: NSViewRepresentable {
    let probe: ChipProbe

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughView()
        probe.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { probe.view = view }

    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// macOS's own shortcuts (System Settings › Keyboard › Keyboard Shortcuts).
/// `RegisterEventHotKey` accepts a combination the system already holds
/// and the system then consumes the key first, so the handler never runs
/// and the registration's return says nothing (#55: ⌥A, Show Notification
/// Center, recorded fine and never fired). The list lives in
/// `com.apple.symbolichotkeys`, each entry `enabled` + `value.parameters`
/// = [character, keyCode, AppKit modifier mask].
enum SystemShortcuts {
    static func owns(_ spec: HotkeySpec) -> Bool {
        guard let table = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys") else { return false }
        let wanted = appKitMask(fromCarbon: spec.modifiers)
        return table.values.contains { entry in
            guard let entry = entry as? [String: Any],
                  (entry["enabled"] as? Bool ?? (entry["enabled"] as? Int == 1)),
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Any], parameters.count >= 3,
                  let keyCode = (parameters[1] as? NSNumber)?.uint32Value,
                  let mask = (parameters[2] as? NSNumber)?.uint32Value else { return false }
            return keyCode == spec.keyCode && mask & Self.allModifiers == wanted
        }
    }

    private static let allModifiers = UInt32(NSEvent.ModifierFlags([.shift, .control, .option, .command]).rawValue)

    private static func appKitMask(fromCarbon mods: UInt32) -> UInt32 {
        var flags: NSEvent.ModifierFlags = []
        if mods & UInt32(controlKey) != 0 { flags.insert(.control) }
        if mods & UInt32(optionKey) != 0 { flags.insert(.option) }
        if mods & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if mods & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return UInt32(flags.rawValue)
    }
}
