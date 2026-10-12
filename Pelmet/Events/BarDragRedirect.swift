// BarDragRedirect.swift
// A ⌘-drag from the menu bar let go over the open panel files the icon in
// the section under the pointer. macOS reads any drop below the bar as a
// removal, and on macOS 27 that takes the whole app off the bar ("Disallowed
// application", or a Control Center module switched off). So while such a
// drag is over the panel, this tap tells the apps every drag event and the
// mouse-up came where the drag began: MenuBarAgent keeps the icon in its slot
// ("reordered"), and Pelmet does the move itself. The drag events matter,
// not just the mouse-up: MenuBarAgent judges a removal by how far below the
// bar the drag went. A mouse-up-only rewrite let go 176pt down still read
// "removed" and disallowed Snib (2026-10-12), the whole-drag rewrite held at
// 187pt. The cursor moves freely, a session tap acts after the window server
// has placed it, and the panel draws the icon's copy under it.
//
// Armed only for one user drag that starts while the panel is open, disabled
// otherwise, so no other mouse event ever passes through it.

import AppKit
import PelmetEngine

nonisolated final class BarDragRedirect: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    /// CG global coordinates (top-left origin), like the events.
    private var zone = CGRect.null
    private var anchor = CGPoint.zero
    /// The mouse-up the armed tap saw (CG point) and whether it rewrote it:
    /// the main thread acts on the tap's word, never on its own reading.
    private var drop: (point: CGPoint, rewrote: Bool)?
    /// The pointer as the user moved it: once the tap rewrites, AppKit
    /// (`NSEvent.mouseLocation`, the monitors' events) reads the anchor.
    private var pointer: CGPoint?
    private var height: CGFloat = 0
    private var tap: CFMachPort?

    /// `zone` and `anchor` in Cocoa screen points (y up).
    @MainActor
    func arm(zone: CGRect, anchor: CGPoint) -> Bool {
        if tap == nil, !start() { return false }
        let height = NSScreen.screens.first?.frame.height ?? 0
        lock.withLock {
            self.zone = CGRect(x: zone.minX, y: height - zone.maxY, width: zone.width, height: zone.height)
            self.anchor = CGPoint(x: anchor.x, y: height - anchor.y)
            self.height = height
            drop = nil
            pointer = nil
            armed = true
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return true
    }

    /// The panel moved or grew under the drag (it opens animated).
    @MainActor
    func update(zone: CGRect) {
        let height = NSScreen.screens.first?.frame.height ?? 0
        lock.withLock {
            self.zone = CGRect(x: zone.minX, y: height - zone.maxY, width: zone.width, height: zone.height)
        }
    }

    /// Where the user's pointer really is (Cocoa screen points), from the
    /// last event the armed tap saw; nil before the first.
    func realPointer() -> CGPoint? {
        lock.withLock { pointer.map { CGPoint(x: $0.x, y: height - $0.y) } }
    }

    /// The armed drag's mouse-up, once (Cocoa screen points): where it really
    /// was, and whether the apps were told it came at the anchor. Nil when
    /// the tap never saw it (disabled by a timeout): nothing was rewritten.
    func takeDrop() -> (point: CGPoint, rewrote: Bool)? {
        lock.withLock {
            defer { drop = nil }
            return drop.map { (CGPoint(x: $0.point.x, y: height - $0.point.y), $0.rewrote) }
        }
    }

    @MainActor
    func disarm() {
        lock.withLock { armed = false }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    private func start() -> Bool {
        let mask = [CGEventType.leftMouseDragged, .leftMouseUp]
            .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let redirect = Unmanaged<BarDragRedirect>.fromOpaque(userInfo).takeUnretainedValue()
                return redirect.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            PelmetLog.log("band: drag redirect tap unavailable")
            return false
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        self.tap = tap
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
            CFRunLoopRun()
        }
        thread.qualityOfService = .userInteractive
        thread.name = "pelmet.drag-redirect"
        thread.start()
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if lock.withLock({ armed }), let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let anchor: CGPoint? = lock.withLock {
            guard armed else { return nil }
            pointer = event.location
            let rewrite = zone.contains(event.location)
            if type == .leftMouseUp {
                // The drag ends here whatever happens: the next one arms afresh.
                armed = false
                drop = (event.location, rewrite)
            }
            return rewrite ? self.anchor : nil
        }
        // Off until the next arm, even if the main thread never hears of it.
        if type == .leftMouseUp, let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let anchor { event.location = anchor }
        return Unmanaged.passUnretained(event)
    }
}
