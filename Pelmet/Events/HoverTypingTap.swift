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
    private var tap: CFMachPort?
    private let onType: @MainActor (String) -> Void

    init(onType: @escaping @MainActor (String) -> Void) {
        self.onType = onType
    }

    /// `zone` in Cocoa screen points (y up). False when the tap can't be made.
    @MainActor
    @discardableResult
    /// `keepingPresses`: re-armed for the grace after the first key, whose
    /// release is still to come and must not reach the app in front.
    func arm(zone: CGRect, keepingPresses: Bool = false) -> Bool {
        if tap == nil, !start() { return false }
        let height = NSScreen.screens.first?.frame.height ?? 0
        lock.withLock {
            self.zone = CGRect(x: zone.minX, y: height - zone.maxY, width: zone.width, height: zone.height)
            // A press whose release the tap never saw is not one to wait for.
            if !keepingPresses { swallowed.removeAll() }
            armed = true
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return true
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
            if idle, let tap { CGEvent.tapEnable(tap: tap, enable: false) }
            return ours ? nil : Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate]),
              let typed = Self.typed(by: event)
        else { return Unmanaged.passUnretained(event) }
        // The pointer, not the event's own location: a key carries none.
        let pointer = CGEvent(source: nil)?.location ?? event.location
        let took = lock.withLock { () -> Bool in
            guard armed, zone.contains(pointer) else { return false }
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
