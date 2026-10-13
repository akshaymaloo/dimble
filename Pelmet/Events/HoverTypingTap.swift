// HoverTypingTap.swift
// A panel a hover opened takes no keys, so a hover passing by never steals
// the typing from the app in front. Once the pointer rests on its glass the
// person is looking at it, though: the first printable key typed then starts
// a search there. Only a session tap can swallow a key before the app in
// front has it (a global NSEvent monitor only watches), so this one does, and
// tells the panel which character it took. The panel takes the keys from
// there (`makeDeliberate`), and the tap goes back to sleep.
//
// Armed only while a hover-opened panel is up, disabled otherwise, so no
// other key ever passes through it. It reads the pointer, the modifiers and
// the character; what the key means is the panel's.
//
// A field being typed into in another of Pelmet's windows (the command bar's,
// a Settings field) or a shortcut recorder listening keeps the keys: the tap
// takes nothing then, wherever the pointer rests. The command bar opens over
// the same corner, and the letters typed into it went to the panel's search
// (⌥⌘K over a hover panel). Settings in front with nothing focused leaves
// type-to-search as it is.

import AppKit
import PelmetEngine

nonisolated final class HoverTypingTap: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    /// The panel's glass in CG global coordinates (top-left origin), like the
    /// events.
    private var zone = CGRect.null
    /// Key codes swallowed at key-down: their key-up is swallowed too, or the
    /// app in front would see a release it never saw the press of.
    private var swallowed: Set<Int64> = []
    /// Another of Pelmet's windows is key with a field or a recorder taking
    /// the typing: what is typed is that window's.
    private var yielding = false
    /// The panel's own window (main thread only): key once the first key
    /// made it deliberate, while the grace still wants the keys.
    private weak var panel: NSWindow?
    private var keyObservers: [NSObjectProtocol] = []
    private var focusMonitor: Any?
    private var tap: CFMachPort?
    private let onType: @MainActor (String) -> Void

    init(onType: @escaping @MainActor (String) -> Void) {
        self.onType = onType
    }

    /// Posted by a window whose field took the focus late, after the key
    /// change this tap looked at (the command bar's retried focus): it
    /// looks again.
    static let focusMoved = Notification.Name("app.fif7y.Pelmet.typingFocusMoved")

    /// `zone` in Cocoa screen points (y up), `window` the panel's. False when
    /// the tap can't be made.
    @MainActor
    @discardableResult
    /// `keepingPresses`: re-armed for the grace after the first key, whose
    /// release is still to come and must not reach the app in front.
    func arm(zone: CGRect, window: NSWindow?, keepingPresses: Bool = false) -> Bool {
        if tap == nil, !start() { return false }
        if keyObservers.isEmpty { observeKeyWindows() }
        let height = NSScreen.screens.first?.frame.height ?? 0
        panel = window
        lock.withLock {
            self.zone = CGRect(x: zone.minX, y: height - zone.maxY, width: zone.width, height: zone.height)
            // A press whose release the tap never saw is not one to wait for.
            if !keepingPresses { swallowed.removeAll() }
            armed = true
        }
        noteKeyWindow(arming: true)
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return true
    }

    @MainActor
    private func observeKeyWindows() {
        keyObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let resigning = name == NSWindow.didResignKeyNotification
                    ? (note.object as AnyObject?).map(ObjectIdentifier.init) : nil
                MainActor.assumeIsolated { self?.noteKeyWindow(resigning: resigning) }
                // A window's field can take the focus a turn after the window
                // became key.
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.noteKeyWindow() } }
            }
        }
        keyObservers.append(NotificationCenter.default.addObserver(forName: Self.focusMoved, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.noteKeyWindow() }
        })
        // A click or a Tab in one of Pelmet's windows moves the focus into a
        // field or out of it with no notification: looked at again once the
        // event has done its work.
        focusMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.noteKeyWindow() } }
            return event
        }
    }

    /// Whether another of Pelmet's windows takes the typing, read on the
    /// main thread for the tap's. `resigning` is on its way out of key status.
    @MainActor
    private func noteKeyWindow(resigning: ObjectIdentifier? = nil, arming: Bool = false) {
        let typist = NSApp.keyWindow
            .flatMap { $0 === panel || ObjectIdentifier($0) == resigning ? nil : $0 }
            .flatMap(Self.typist(in:))
        let (changed, armed) = lock.withLock { () -> (Bool, Bool) in
            defer { yielding = typist != nil }
            return (yielding != (typist != nil), self.armed)
        }
        guard armed, changed || (arming && typist != nil) else { return }
        if let typist {
            PelmetLog.log("panel: typing over the hover panel stays with \(typist), it has the keys")
        } else {
            PelmetLog.log("panel: typing over the hover panel is the panel's again")
        }
    }

    /// What in the key `window` takes typing: a text field or view being
    /// edited, or a shortcut recorder listening. Nil when nothing there wants
    /// the keys.
    @MainActor
    private static func typist(in window: NSWindow) -> String? {
        let name = window.title.isEmpty ? String(describing: type(of: window)) : window.title
        if ShortcutRecorder.listening > 0 { return "a shortcut recorder in \(name)" }
        if (window.firstResponder as? NSTextView)?.isEditable == true { return "a text field in \(name)" }
        return nil
    }

    /// The panel moved or grew.
    @MainActor
    func update(zone: CGRect) {
        let height = NSScreen.screens.first?.frame.height ?? 0
        lock.withLock {
            self.zone = CGRect(x: zone.minX, y: height - zone.maxY, width: zone.width, height: zone.height)
        }
    }

    /// Off, unless a swallowed key is still down: its release goes with it.
    @MainActor
    func disarm() {
        let idle = lock.withLock { () -> Bool in
            armed = false
            return swallowed.isEmpty
        }
        if idle, let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    private func start() -> Bool {
        let mask = [CGEventType.keyDown, .keyUp]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let typing = Unmanaged<HoverTypingTap>.fromOpaque(userInfo).takeUnretainedValue()
                return typing.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            PelmetLog.log("panel: typing tap unavailable")
            return false
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        self.tap = tap
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
            CFRunLoopRun()
        }
        thread.qualityOfService = .userInteractive
        thread.name = "pelmet.hover-typing"
        thread.start()
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if lock.withLock({ armed || !swallowed.isEmpty }), let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            let (ours, idle) = lock.withLock { () -> (Bool, Bool) in
                let ours = swallowed.remove(code) != nil
                return (ours, !armed && swallowed.isEmpty)
            }
            // Off until the next arm, even if the main thread never hears of it.
            // An arm that came in between may have enabled it first: on again.
            if idle, let tap {
                CGEvent.tapEnable(tap: tap, enable: false)
                if lock.withLock({ armed }) { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return ours ? nil : Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate]),
              let typed = Self.typed(by: event)
        else { return Unmanaged.passUnretained(event) }
        // A held key repeats for whoever has its press: a key held down in the
        // app in front when the panel came up stays that app's, release and
        // all, or the key sticks there (a VM, a remote desktop, a game).
        let repeating = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        // The pointer, not the event's own location: a key carries none.
        let pointer = CGEvent(source: nil)?.location ?? event.location
        let took = lock.withLock { () -> Bool in
            guard armed, !yielding, zone.contains(pointer), !repeating || swallowed.contains(code) else { return false }
            swallowed.insert(code)
            return true
        }
        guard took else { return Unmanaged.passUnretained(event) }
        let onType = onType
        DispatchQueue.main.async { MainActor.assumeIsolated { onType(typed) } }
        return nil
    }

    /// What the key types, when that is something the panel's search takes: a
    /// letter, a digit, a symbol. Not Esc, Return, Tab, Delete, an arrow or
    /// another function key, and not a space before any letter.
    private static func typed(by event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return nil }
        let typed = String(utf16CodeUnits: buffer, count: length)
        return PanelKey.query("", typing: typed) == nil ? nil : typed
    }
}
