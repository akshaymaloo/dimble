// LiveMirror.swift
// Live mode (spike, `-pelmet.debug.liveMirror YES`): while a Live Activity
// runs, the pill shows beside the « and the hidden icons stay hidden.
//
// MenuBarAgent takes the pill off the bar under any hide assertion, so live
// mode holds none: the assertion goes (`engine.holdLift`), the icons it hid
// come back onto the bar, and a picture of the concealed bar, taken just
// before, covers [left limit, «) on every display. Right of the « the bar is
// live: with no assertion Sound, Battery and the like come back there and
// push the « left, so the cover's end follows it.
//
// The pill is drawn by Dimble, from one still: the pill's frame and its
// children are read over AX (MenuBarAgent, subrole AXLiveActivity); a still
// of the pill (Pelmet's own windows and foreign surfaces left out) keeps its
// capsule and its logos, the text children are blanked out of it and drawn
// live by Dimble at their AX frames. An AXObserver on the pill's elements
// says when a text or the layout changes, with a slow poll behind it. The
// still is retaken only when the image children change (count, description,
// relative frames) or the pill's width does. A click on the mirror is an AX
// press on the real pill. A click on the « lifts the cover (the real bar,
// hidden icons and pill, shows) and a second one, or ten seconds, puts it
// back. When the activity ends the assertion comes back under the cover,
// which lifts once the bar beneath has settled
// (`TransitionCoordinator.endLive`).
//
// Every step logs with a `livemirror:` prefix.

import AppKit
import ApplicationServices
import PelmetCore
import PelmetEngine
import QuartzCore
import ImageIO
import ScreenCaptureKit

// MARK: - The pill over AX

/// One copy of the pill in MenuBarAgent's tree (one per display).
nonisolated struct PillCopy: @unchecked Sendable {
    let element: AXUIElement
    /// CG global, top-left origin.
    let frame: CGRect
    let text: String
    let name: String
}


/// One element under the pill.
nonisolated struct ElementBox: @unchecked Sendable { let list: [AXUIElement] }

nonisolated struct PillNode: @unchecked Sendable {
    let element: AXUIElement
    let role: String
    /// AXIdentifier, else AXDescription.
    let key: String
    let value: String
    /// CG global.
    let frame: CGRect
    let isLeaf: Bool
}

nonisolated struct PillTree: @unchecked Sendable {
    let pill: AXUIElement
    let frame: CGRect
    let nodes: [PillNode]

    /// A leaf that covers the pill (its hit area, "Expanded"): not content.
    func isBackdrop(_ node: PillNode) -> Bool {
        node.isLeaf && node.role != "AXStaticText" && node.frame.width >= frame.width * 0.9 && node.frame.height >= frame.height * 0.9
    }
    var texts: [PillNode] { nodes.filter { $0.role == "AXStaticText" && $0.frame.width > 0 }.sorted { $0.frame.minX < $1.frame.minX } }
    /// Logos and glyphs: every other leaf with a frame.
    var images: [PillNode] {
        nodes.filter { $0.isLeaf && $0.role != "AXStaticText" && $0.frame.width > 0 && !isBackdrop($0) }.sorted { $0.frame.minX < $1.frame.minX }
    }
    /// What the pill looks like: its frame joined with the hit area's.
    var visual: CGRect {
        nodes.filter(isBackdrop).reduce(frame) { $0.union($1.frame) }
    }
    /// What forces a new still: the image children and the pill's width.
    struct Look {
        var width: CGFloat
        var items: [(key: String, rect: CGRect)]

        /// Why `self` needs a new still after `old`, or nil: the pill's width,
        /// the image children (count, key) or a relative frame moved by more
        /// than a point (AX frames drift by half a point as the bar shifts).
        func change(from old: Look) -> String? {
            if abs(width - old.width) > 1 { return "pill width \(fmt(old.width)) → \(fmt(width))" }
            if items.count != old.items.count { return "image children \(old.items.count) → \(items.count)" }
            for (new, was) in zip(items, old.items) {
                if new.key != was.key { return "image child \(was.key) → \(new.key)" }
                let r = new.rect, o = was.rect
                if abs(r.minX - o.minX) > 1 || abs(r.minY - o.minY) > 1 || abs(r.width - o.width) > 1 || abs(r.height - o.height) > 1 {
                    return "\(new.key) frame \(fmt(o.minX)),\(fmt(o.minY)),\(fmt(o.width))x\(fmt(o.height)) → \(fmt(r.minX)),\(fmt(r.minY)),\(fmt(r.width))x\(fmt(r.height))"
                }
            }
            return nil
        }
        private func fmt(_ v: CGFloat) -> String { String(format: "%.1f", v) }
    }
    var look: Look {
        Look(width: frame.width, items: images.map { ($0.key, CGRect(x: $0.frame.minX - frame.minX, y: $0.frame.minY - frame.minY, width: $0.frame.width, height: $0.frame.height)) })
    }
}

/// Notifications from MenuBarAgent's pill elements, on the main run loop.
nonisolated final class PillObserver: @unchecked Sendable {
    private var observer: AXObserver?
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var _registered = 0
    private var refusals: [Int32: Int] = [:]
    var onEvent: (@Sendable (String) -> Void)?

    static let names = [
        kAXValueChangedNotification, kAXLayoutChangedNotification, kAXMovedNotification, kAXResizedNotification,
        kAXUIElementDestroyedNotification, kAXCreatedNotification, kAXTitleChangedNotification,
    ]

    func start(pid: pid_t) -> Bool {
        var made: AXObserver?
        guard AXObserverCreate(pid, axPillCallback, &made) == .success, let made else { return false }
        observer = made
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(made), .defaultMode)
        return true
    }

    func watch(_ elements: [AXUIElement]) {
        guard let observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for element in elements {
            for name in Self.names {
                let result = AXObserverAddNotification(observer, element, name as CFString, refcon)
                lock.lock()
                if result == .success { _registered += 1 } else if result != .notificationAlreadyRegistered { refusals[result.rawValue, default: 0] += 1 }
                lock.unlock()
            }
        }
    }

    var registration: String {
        lock.lock(); defer { lock.unlock() }
        return "\(_registered) registered" + (refusals.isEmpty ? "" : ", refused \(refusals.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " "))")
    }

    fileprivate func fire(_ name: String) {
        lock.lock(); counts[name, default: 0] += 1; lock.unlock()
        onEvent?(name)
    }

    func drainCounts() -> [String: Int] {
        lock.lock(); defer { lock.unlock(); counts = [:] }
        return counts
    }

    func stop() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        onEvent = nil
    }
}

nonisolated private func axPillCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    Unmanaged<PillObserver>.fromOpaque(refcon).takeUnretainedValue().fire(notification as String)
}

nonisolated enum PillProbe {
    static let identifierPrefix = "live-activity-pill-"
    /// Debug: mirror the pill whose AXDescription is this ("myVW") when
    /// several activities run; empty = the first one found.
    static var preferredName: String { UserDefaults.standard.string(forKey: "pelmet.debug.liveMirrorPill") ?? "" }
    static func picks(_ copy: PillCopy, in bounds: CGRect, named: String? = nil) -> Bool {
        guard bounds.contains(CGPoint(x: copy.frame.midX, y: copy.frame.midY)) else { return false }
        let wanted = named ?? preferredName
        return wanted.isEmpty || copy.name == wanted
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attribute(element, kAXPositionAttribute), let size = attribute(element, kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: origin, size: extent)
    }

    /// The compact text the pill shows: its static texts, two levels down.
    static func text(of element: AXUIElement, depth: Int = 4) -> String {
        var parts: [String] = []
        for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            if (attribute(child, kAXRoleAttribute) as? String) == "AXStaticText" {
                if let value = attribute(child, kAXValueAttribute) as? String { parts.append(value) }
            } else if depth > 1 {
                let inner = text(of: child, depth: depth - 1)
                if !inner.isEmpty { parts.append(inner) }
            }
        }
        return parts.joined(separator: " ")
    }

    /// Frame and text of a copy already found; nil when it is gone.
    static func read(_ element: AXUIElement) -> (frame: CGRect, text: String)? {
        guard let frame = frame(of: element), frame.width > 0 else { return nil }
        return (frame, text(of: element))
    }

    /// Frames of every element with this identifier in the agent's tree
    /// (CG global): the clock, once per bar copy.
    static func frames(ofIdentifier wanted: String) -> [CGRect] {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: PelmetBundle.agentID).first
        else { return [] }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.6)
        var found: [CGRect] = []
        func walk(_ element: AXUIElement, _ depth: Int) {
            if let id = attribute(element, kAXIdentifierAttribute) as? String, id == wanted {
                if let frame = frame(of: element), frame.width > 0 { found.append(frame) }
                return
            }
            guard depth > 0 else { return }
            for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(child, depth - 1) }
        }
        walk(app, 8)
        return found
    }

    /// The pill's children: texts, logos, the hit area. Nil when it is gone.
    /// MenuBarAgent's AX application element.
    static func agentApp() -> AXUIElement? {
        NSRunningApplication.runningApplications(withBundleIdentifier: PelmetBundle.agentID).first
            .map { AXUIElementCreateApplication($0.processIdentifier) }
    }

    /// Whether the expanded card is on screen: a MenuBarAgent window below
    /// the bar (the bar's own sits at y 0) holding a live-activity group.
    /// The card's window stays listed for the whole collapse (~0.8 s).
    static func cardIsOpen() -> Bool { cardProbe().open }

    /// The same read with what it saw, for the log: the agent's windows with
    /// their frames, a star on the one holding the live-activity group.
    static func cardProbe() -> (open: Bool, detail: String) {
        guard let app = agentApp() else { return (false, "no agent") }
        AXUIElementSetMessagingTimeout(app, 0.6)
        func hasActivity(_ element: AXUIElement, _ depth: Int) -> Bool {
            if (attribute(element, kAXSubroleAttribute) as? String) == "AXLiveActivity" { return true }
            guard depth < 4 else { return false }
            return ((attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []).contains { hasActivity($0, depth + 1) }
        }
        var raw: AnyObject?
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw)
        let windows = (raw as? [AXUIElement]) ?? []
        var open = false
        var parts: [String] = []
        for window in windows {
            guard let frame = frame(of: window) else { parts.append("?"); continue }
            let holds = frame.minY >= 20 && hasActivity(window, 0)
            if holds { open = true }
            parts.append("\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))\(holds ? "*" : "")")
        }
        return (open, "ax \(error == .success ? "ok" : "err \(error.rawValue)"), \(windows.count) window(s) [\(parts.joined(separator: "; "))]")
    }

    /// Presses the pill that sits in `bounds`, looked up fresh (the element
    /// in hand may be a copy the agent has since replaced); the one in hand
    /// is the fallback. Returns what happened, for the log, and the fresh copy.
    static func press(in bounds: CGRect, named: String?, kept: AXUIElement?) -> (result: String, fresh: PillCopy?) {
        let fresh = copies().first { picks($0, in: bounds, named: named) }
        var notes: [String] = []
        if let fresh {
            let error = AXUIElementPerformAction(fresh.element, kAXPressAction as CFString)
            if error == .success { return ("success (fresh pill)", fresh) }
            notes.append("fresh pill error \(error.rawValue)")
        } else {
            notes.append("no pill found")
        }
        if let kept {
            let error = AXUIElementPerformAction(kept, kAXPressAction as CFString)
            notes.append(error == .success ? "kept pill success" : "kept pill error \(error.rawValue)")
        }
        return (notes.joined(separator: ", "), fresh)
    }

    static func readTree(_ pill: AXUIElement) -> PillTree? {
        guard let frame = frame(of: pill), frame.width > 0 else { return nil }
        var nodes: [PillNode] = []
        func walk(_ element: AXUIElement, _ depth: Int) {
            for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                let role = (attribute(child, kAXRoleAttribute) as? String) ?? ""
                let id = (attribute(child, kAXIdentifierAttribute) as? String) ?? ""
                let description = (attribute(child, kAXDescriptionAttribute) as? String) ?? ""
                let value = role == "AXStaticText" ? ((attribute(child, kAXValueAttribute) as? String) ?? "") : ""
                let kids = depth < 6 ? ((attribute(child, kAXChildrenAttribute) as? [AXUIElement]) ?? []) : []
                nodes.append(PillNode(element: child, role: role, key: id.isEmpty ? description : id, value: value,
                                      frame: self.frame(of: child) ?? .zero, isLeaf: kids.isEmpty))
                if !kids.isEmpty { walkKids(kids, depth + 1) }
            }
        }
        func walkKids(_ kids: [AXUIElement], _ depth: Int) {
            for child in kids {
                let role = (attribute(child, kAXRoleAttribute) as? String) ?? ""
                let id = (attribute(child, kAXIdentifierAttribute) as? String) ?? ""
                let description = (attribute(child, kAXDescriptionAttribute) as? String) ?? ""
                let value = role == "AXStaticText" ? ((attribute(child, kAXValueAttribute) as? String) ?? "") : ""
                let sub = depth < 6 ? ((attribute(child, kAXChildrenAttribute) as? [AXUIElement]) ?? []) : []
                nodes.append(PillNode(element: child, role: role, key: id.isEmpty ? description : id, value: value,
                                      frame: self.frame(of: child) ?? .zero, isLeaf: sub.isEmpty))
                if !sub.isEmpty { walkKids(sub, depth + 1) }
            }
        }
        walk(pill, 0)
        return PillTree(pill: pill, frame: frame, nodes: nodes)
    }

    /// Every pill in the agent's tree.
    static func copies() -> [PillCopy] {
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: PelmetBundle.agentID).first
        else { return [] }
        let app = AXUIElementCreateApplication(agent.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.6)
        var found: [PillCopy] = []
        collect(app, depth: 8, into: &found)
        return found
    }

    private static func collect(_ element: AXUIElement, depth: Int, into found: inout [PillCopy]) {
        if let id = attribute(element, kAXIdentifierAttribute) as? String, id.hasPrefix(identifierPrefix) {
            if let read = read(element) {
                let name = (attribute(element, kAXDescriptionAttribute) as? String) ?? id
                found.append(PillCopy(element: element, frame: read.frame, text: read.text, name: name))
            }
            return
        }
        guard depth > 0 else { return }
        for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            collect(child, depth: depth - 1, into: &found)
        }
    }
}


// MARK: - Live mode

@MainActor
final class LiveMirror {
    static let flagKey = "pelmet.debug.liveMirror"
    /// Debug: while true live mode is left (or not entered), for cycling it by hand.
    static let suspendKey = "pelmet.debug.liveMirrorSuspend"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: flagKey) }

    private static let pollInterval = Duration.milliseconds(250)
    /// The AX fallback read, in ticks: the observer is the way in, this is the net.
    private static let fallbackEvery = 8
    /// Points the mirror keeps clear of the cover's right end.
    private static let gap: CGFloat = 3
    private static let coverSafety: TimeInterval = 3600
    private static let liftedCoverReturn: TimeInterval = 10

    /// One display's share of live mode.
    private final class Side {
        let id: CGDirectDisplayID
        let screen: NSScreen
        let scDisplay: SCDisplay
        var picture: ConcealGhostOverlay.BarSnapshot?
        var cover: ConcealGhostOverlay.GhostSet?
        var coverMinX: CGFloat = 0
        var coverMaxX: CGFloat = 0
        var pill: PillCopy?
        var tree: PillTree?
        var look: PillTree.Look?
        var snapping = false
        var snapshots = 0
        var texts: [String] = []
        var textChangedAt: Date?
        /// The pill's AX texts as of the last still: a change in them is what
        /// the text-triggered snapshot compares against.
        var snapTexts: [String]?
        /// The one trailing snapshot waiting for the rate limit to pass.
        var trailing: Task<Void, Never>?
        var misses = 0
        /// The mirror: the still with the texts blanked, and the texts over it.
        let container = CALayer()
        let base = CALayer()
        var textLayers: [CATextLayer] = []
        var layerAttached = false
        var visual: CGRect?
        var mirrorGlobal: NSRect?
        var observer: PillObserver?
        var refresh: Task<Void, Never>?

        init(id: CGDirectDisplayID, screen: NSScreen, scDisplay: SCDisplay) {
            self.id = id; self.screen = screen; self.scDisplay = scDisplay
            container.addSublayer(base)
        }
        var scale: CGFloat { screen.backingScaleFactor }
        var bounds: CGRect { CGDisplayBounds(id) }
    }

    private weak var appState: AppState?
    private var sides: [Side] = []
    private(set) var isActive = false
    private var entering = false, exiting = false
    private var wanted = false
    private var loop: Task<Void, Never>?
    private var lastChevron: NSRect?
    private var coverLifted = false
    private var liftedReturn: Task<Void, Never>?
    private var lastBlockedWhy = ""
    private var lastSummaryAt = Date()
    private var tickCount = 0
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var orderKeeper: Task<Void, Never>?
    private var pendingReveal: RevealReason?
    private var themeObserver: NSObjectProtocol?

    /// A reveal the live mirror handed the bar to (`beginHandOver`): the
    /// pill and the mirror are away, the cover stays up until the reveal's
    /// swap has landed (`revealLanded`), and live mode comes back by the
    /// loop once the re-hide has rested.
    private var handingOver = false
    private var released = false
    private var handOverWatchdog: Task<Void, Never>?
    private var lastHoverNote = Date.distantPast

    /// The last still of each display, kept across a reveal (not across the
    /// end of live mode): reused when the pill's look is unchanged, so the
    /// return to live mode takes no second capture.
    private struct KeptStill { var look: PillTree.Look; var image: CGImage; var at: Date; var texts: [String] }
    private var kept: [CGDirectDisplayID: KeptStill] = [:]
    /// Drawn graphics (a ring, a bar) usually move with the pill's text. A
    /// text change takes a new still, at most once per interval per display
    /// (a ticking countdown must not keep the capture dot lit); changes inside
    /// the window coalesce into one trailing snapshot. Kept across live mode.
    static let textSnapshotInterval: TimeInterval = 30
    private var textSnapAt: [CGDirectDisplayID: Date] = [:]

    init(appState: AppState) { self.appState = appState }

    // MARK: Entry points

    func activitiesChanged(running: Bool) {
        guard Self.enabled else { return }
        if running != wanted { PelmetLog.log("livemirror: activities \(running ? "running" : "none") — wanted \(running)") }
        wanted = running
        if loop == nil { startLoop() }
    }

    /// A reveal asked for while live mode has the bar. The «, a hover and the
    /// hotkey hand the bar to the normal reveal: the pill and the mirror go,
    /// the cover stays up while the one swap lands, and live mode comes
    /// back after the re-hide. A hover on the mirror itself is no reveal
    /// (the pointer is on its way to a click). Every other trigger (Apply,
    /// the editor, a policy) is held off while live mode has the bar.
    func intercepts(reveal reason: RevealReason) -> Bool {
        guard isActive else { return false }
        if handingOver || exiting { return false }
        if entering {
            switch reason {
            case .hover, .statusItem, .click, .doubleClick, .hotkey:
                pendingReveal = reason
                PelmetLog.log("livemirror: reveal(\(reason)) asked while live mode starts — it runs once live mode has settled")
            default:
                PelmetLog.log("livemirror: reveal(\(reason)) blocked — live mode has the bar")
            }
            return true
        }
        switch reason {
        case .hover:
            if pointerOnMirror() {
                if Date().timeIntervalSince(lastHoverNote) > 2 {
                    lastHoverNote = Date()
                    PelmetLog.log("livemirror: hover on the mirror — no reveal, the pointer is on its way to a click")
                }
                return true
            }
            beginHandOver(reason)
            return false
        case .statusItem, .click, .doubleClick, .hotkey:
            beginHandOver(reason)
            return false
        default:
            PelmetLog.log("livemirror: reveal(\(reason)) blocked — live mode has the bar")
            return true
        }
    }

    /// The Live Activities item's own click (the existing lift): in live
    /// mode it only lifts the cover and puts it back.
    func interceptsItemClick() -> Bool {
        guard isActive, !handingOver else { return isActive }
        toggleCover("item")
        return true
    }

    private func pointerOnMirror() -> Bool {
        let point = NSEvent.mouseLocation
        return sides.contains { side in
            side.mirrorGlobal.map { !side.container.isHidden && $0.insetBy(dx: -6, dy: -6).contains(point) } ?? false
        }
    }

    private func beginHandOver(_ reason: RevealReason) {
        handingOver = true
        released = false
        liftedReturn?.cancel()
        if coverLifted {
            coverLifted = false
            setCoversShown(true, why: "hand-over")
        }
        PelmetLog.log("livemirror: reveal(\(reason)) — the bar goes to the normal reveal, pill and mirror away, cover up")
        for side in sides {
            side.refresh?.cancel()
            side.trailing?.cancel()
            side.trailing = nil
            side.observer?.stop()
            side.observer = nil
            CATransaction.begin(); CATransaction.setDisableActions(true)
            side.container.isHidden = true
            CATransaction.commit()
        }
        let mouse: Bool = { switch reason { case .click, .doubleClick, .statusItem: true; default: false } }()
        Task { @MainActor in await self.closeCard(why: "reveal(\(reason))", mouseDismisses: mouse) }
        handOverWatchdog?.cancel()
        handOverWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled, self.handingOver, !self.released else { return }
            PelmetLog.log("livemirror: no reveal came for the hand-over — live mode carries on")
            self.handingOver = false
            for side in self.sides {
                side.container.isHidden = false
                self.startObserving(side)
            }
        }
    }

    /// The coordinator's reveal is about to take the engine: live mode's
    /// hold ends with no swap of its own, so the reveal's is the only one.
    func releaseForReveal() async {
        guard handingOver, !released, let appState else { return }
        released = true
        handOverWatchdog?.cancel()
        ConcealGhostOverlay.liveModeBlocksCaptures = false
        await appState.engine.releaseLiftHold()
        PelmetLog.log("livemirror: hold released — the reveal's assertion is the swap")
    }

    /// The reveal's swap has landed: the pill is gone for good, live mode
    /// is over until the re-hide. The cover comes down once the bar rests
    /// beneath it (under the reveal's own cover, which lifts after).
    func revealLanded() async {
        guard handingOver, released, let appState else { return }
        let covers = sides.compactMap(\.cover)
        for side in sides { side.observer?.stop(); side.observer = nil }
        sides = []
        isActive = false
        handingOver = false
        released = false
        lastChevron = nil
        appState.transitions.liveModeActive = false
        PelmetLog.log("livemirror: reveal landed — live mode is off until the re-hide")
        Task { @MainActor in
            let started = Date()
            await appState.waitUntilQuiesced(interval: 0.15, deadline: 2, poll: .milliseconds(30))
            for cover in covers { cover.dismiss() }
            PelmetLog.log("livemirror: hand-over cover down at \(Int(-started.timeIntervalSinceNow * 1000))ms")
        }
    }

    // MARK: The card

    /// The expanded card is closed by an AX press on the pill again (the
    /// second press collapses it, ~0.8s), or by the click outside it. Cancel
    /// actions are unsupported on the card, the pill and its window (error
    /// -25206) and an Escape posted to MenuBarAgent's pid does nothing.
    @discardableResult
    private func pressPill(_ why: String, side: Side? = nil) async -> String {
        guard let side = side ?? sides.first(where: { $0.pill != nil }) ?? sides.first else { return "no display" }
        let bounds = side.bounds
        let kept = ElementBox(list: side.pill.map { [$0.element] } ?? [])
        let name = side.pill?.name
        let started = Date()
        let (result, fresh) = await Task.detached(priority: .userInitiated) { PillProbe.press(in: bounds, named: name, kept: kept.list.first) }.value
        if let fresh { side.pill = fresh }
        let text = "\(result) in \(Int(-started.timeIntervalSinceNow * 1000))ms"
        PelmetLog.log("livemirror: card — AX press on the pill (\(why)) → \(text)")
        return text
    }

    private func cardIsOpen() async -> Bool {
        await Task.detached(priority: .userInitiated) { PillProbe.cardIsOpen() }.value
    }

    /// Closes the card if it is open. `mouseDismisses`: a click started this,
    /// and the click is already an outside interaction that collapses the
    /// card; a press now would interrupt that collapse and leave it open.
    private func closeCard(why: String, mouseDismisses: Bool) async {
        guard await cardIsOpen() else { return }
        let started = Date()
        if mouseDismisses {
            PelmetLog.log("livemirror: card open (\(why)) — the click closes it")
        } else {
            PelmetLog.log("livemirror: card open (\(why)) — closing it")
            await pressPill(why)
        }
        for _ in 0..<14 {
            try? await Task.sleep(for: .milliseconds(100))
            if !(await cardIsOpen()) {
                PelmetLog.log("livemirror: card closed \(Int(-started.timeIntervalSinceNow * 1000))ms after (\(why))")
                return
            }
        }
        PelmetLog.log("livemirror: card still open 1.4s after (\(why))\(mouseDismisses ? " — pressing the pill" : "")")
        if mouseDismisses { await pressPill(why) }
    }

    private func startLoop() {
        if screenObserver == nil {
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isActive, !self.exiting, !self.entering else { return }
                    PelmetLog.log("livemirror: displays changed — leaving live mode, it re-enters")
                    await self.exit("displays changed")
                }
            }
        }
        if spaceObserver == nil {
            spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
            ) { [weak self] _ in Task { @MainActor in await self?.backdropMayHaveChanged("the Space changed") } }
        }
        if themeObserver == nil {
            themeObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
            ) { [weak self] _ in Task { @MainActor in await self?.backdropMayHaveChanged("the appearance changed") } }
        }
        startOrderKeeper()
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let suspended = UserDefaults.standard.bool(forKey: Self.suspendKey)
                let desired = self.wanted && !suspended && Self.enabled
                if self.entering || self.exiting || self.handingOver {
                    // a step is running
                } else if desired, !self.isActive {
                    if let why = await self.cannotEnter() {
                        if why != self.lastBlockedWhy { self.lastBlockedWhy = why; PelmetLog.log("livemirror: waiting to enter — \(why)") }
                    } else {
                        self.lastBlockedWhy = ""
                        await self.enter()
                    }
                } else if !desired, self.isActive {
                    await self.exit(suspended ? "suspended (debug)" : "activity ended")
                } else if self.isActive {
                    await self.tick()
                }
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func cannotEnter() async -> String? {
        guard let appState else { return "no app state" }
        if !ScreenRecordingAccess.isGranted { return "no Screen Recording" }
        if appState.isRevealed || !appState.currentRevealedSections.isEmpty { return "the bar is out" }
        if appState.isTransitioning { return "a transition runs" }
        if appState.panelShowsReveal { return "the panel is up" }
        if appState.liftHoldReason != nil { return "a lift has the bar" }
        if appState.transitions.coversInFlight { return "a cover is still up" }
        if appState.chevronWindowFrame == nil { return "no chevron window" }
        if !(await appState.engine.holdsAssertion) { return "no assertion held — the pill shows on its own" }
        return nil
    }

    // MARK: Geometry

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }
    private var primaryMaxX: CGFloat { NSScreen.screens.first?.frame.maxX ?? 0 }

    /// The chevron's left edge on `side`'s display: its window's offset from
    /// its own display's right edge, translated (the bars mirror right-anchored).
    private func chevronMinX(_ chevron: NSRect, on side: Side) -> CGFloat {
        let home = NSScreen.screens.first { NSMouseInRect(NSPoint(x: chevron.midX, y: chevron.midY), $0.frame, false) } ?? side.screen
        return chevron.minX + (side.screen.frame.maxX - home.frame.maxX)
    }

    /// Where a cover may start: right of the notch, and no further left than
    /// what the hidden icons plus the pill can take.
    private func coverLeft(for side: Side, right: CGFloat) -> CGFloat {
        let concealed = appState?.snapshot?.concealed.count ?? 0
        var left = max(right - CGFloat(concealed) * 44 - 360, side.screen.frame.minX + side.screen.frame.width * 0.3)
        if let notch = side.screen.auxiliaryTopRightArea?.minX { left = max(left, notch + 2) }
        return left
    }

    private func cocoa(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: Enter

    private func abort(_ why: String, dropAssertion: Bool = false) async {
        PelmetLog.log("livemirror: enter aborted — \(why)")
        for side in sides {
            side.cover?.dismiss()
            side.observer?.stop()
        }
        sides = []
        if dropAssertion { await appState?.engine.holdLift(false) }
        ConcealGhostOverlay.liveModeBlocksCaptures = false
        appState?.transitions.liveModeActive = false
        isActive = false
    }

    private func enter() async {
        guard let appState, !isActive else { return }
        entering = true
        defer { entering = false }
        // After a re-hide the bar may still be at its reflow.
        await appState.waitUntilQuiesced(interval: 0.3, deadline: 2, poll: .milliseconds(30))
        let started = Date()
        func ms() -> Int { Int(-started.timeIntervalSinceNow * 1000) }
        guard var chevron = appState.chevronWindowFrame,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        else { PelmetLog.log("livemirror: enter refused — no chevron or no shareable content"); return }
        PelmetLog.log("livemirror: enter — chevron \(Int(chevron.minX))..\(Int(chevron.maxX)), \(NSScreen.screens.count) display(s)")
        isActive = true
        appState.transitions.liveModeActive = true
        sides = NSScreen.screens.compactMap { screen in
            guard let id = screen.directDisplayID, let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
            return Side(id: id, screen: screen, scDisplay: display)
        }
        guard !sides.isEmpty else { await abort("no display to film"); return }

        // 1. The picture of the concealed bar, each display from its left
        // limit to the «. Taking it lights the system's capture indicator,
        // which moves the cluster: the « is read again once it has.
        for side in sides {
            let right = chevronMinX(chevron, on: side) - 1
            let left = coverLeft(for: side, right: right)
            let shift = side.screen.frame.maxX - primaryMaxX
            let rect = CGRect(x: left - shift, y: 0, width: right - left, height: 40)
            side.picture = await ConcealGhostOverlay.snapshotSet(of: rect, displays: [side.id], liveMirror: true).first
            guard let picture = side.picture else { await abort("no picture of display \(side.id)"); return }
            PelmetLog.log("livemirror: display \(side.id) picture \(Int(picture.windowFrame.minX))..\(Int(picture.windowFrame.maxX)) (wanted \(Int(left))..\(Int(right)))")
        }
        PelmetLog.log("livemirror: pictures at \(ms())ms")
        try? await Task.sleep(for: .milliseconds(350))
        let before = chevron
        chevron = appState.chevronWindowFrame ?? chevron
        lastChevron = chevron
        PelmetLog.log("livemirror: chevron \(Int(before.minX)) → \(Int(chevron.minX)) after the picture (capture indicator)")
        for side in sides {
            let right = chevronMinX(chevron, on: side) - 1
            guard buildCover(side, left: coverLeft(for: side, right: right), right: right, why: "enter") else {
                await abort("cover won't crop on display \(side.id)"); return
            }
        }
        ConcealGhostOverlay.liveModeBlocksCaptures = true
        PelmetLog.log("livemirror: covers up at \(ms())ms — \(sides.map { "d\($0.id) \(Int($0.coverMinX))..\(Int($0.coverMaxX))" }.joined(separator: ", "))")

        // 2. The assertion goes: the hidden icons come back under the cover,
        // the extras right of the « and the pill after them.
        await appState.engine.holdLift(true)
        let dropped = ms()
        PelmetLog.log("livemirror: assertion down at \(dropped)ms")

        // 3. Wait for the « to stop moving and the pill (with its children) to be there.
        let by = Date().addingTimeInterval(4)
        var movedAt = Date(), seen = chevron
        var firstPill: Int?
        while Date() < by {
            if let now = appState.chevronWindowFrame, abs(now.minX - seen.minX) > 0.5 {
                seen = now; movedAt = Date()
            }
            if sides.contains(where: { $0.pill == nil }) {
                let copies = await Task.detached(priority: .userInitiated) { PillProbe.copies() }.value
                for copy in copies {
                    let mid = CGPoint(x: copy.frame.midX, y: copy.frame.midY)
                    if let side = sides.first(where: { $0.bounds.contains(mid) && PillProbe.picks(copy, in: $0.bounds) }), side.pill == nil {
                        let tree = await Task.detached(priority: .userInitiated) { () -> PillTree? in
                            PillProbe.readTree(copy.element)
                        }.value
                        if let tree, !tree.texts.isEmpty || !tree.images.isEmpty {
                            side.pill = copy
                            side.tree = tree
                            firstPill = firstPill ?? ms()
                        }
                    }
                }
            }
            if sides.allSatisfy({ $0.pill != nil }), Date().timeIntervalSince(movedAt) > 0.3 { break }
            try? await Task.sleep(for: .milliseconds(60))
        }
        PelmetLog.log("livemirror: settled at \(ms())ms — chevron \(Int(chevron.minX)) → \(Int(seen.minX)), pill \(firstPill.map { "\($0)ms" } ?? "never seen")")

        // 4. The cover shrinks to the « where it is now; the pill is drawn.
        if let now = appState.chevronWindowFrame { lastChevron = now }
        if let chevron = lastChevron {
            for side in sides {
                let right = chevronMinX(chevron, on: side) - 1
                buildCover(side, left: side.coverMinX, right: right, why: "settled")
            }
        }
        for side in sides {
            guard let tree = side.tree else { continue }
            await apply(tree, to: side, why: "enter")
            startObserving(side)
        }
        PelmetLog.log("livemirror: live at \(ms())ms (assertion down \(dropped)ms)")
        lastSummaryAt = Date()
        if let reason = pendingReveal {
            pendingReveal = nil
            PelmetLog.log("livemirror: running the reveal(\(reason)) asked while live mode started")
            entering = false
            if reason == .hover { appState.reveal([.hidden], reason: .hover) } else { appState.toggle(reason: reason) }
        }
    }

    // MARK: Cover

    /// The cover over [`left`, `right`] (global Cocoa x) from the kept picture.
    /// The new one goes up before the old one comes down.
    @discardableResult
    private func buildCover(_ side: Side, left: CGFloat, right: CGFloat, why: String) -> Bool {
        guard let picture = side.picture else { return false }
        let shift = side.screen.frame.maxX - primaryMaxX
        let pad = ConcealGhostOverlay.capturePadding
        let span = (left - shift + pad)...(right - shift - pad)
        guard let cropped = ConcealGhostOverlay.cropped([picture], toPrimaryX: span).first,
              let cover = ConcealGhostOverlay.begin(from: [cropped], safety: Self.coverSafety, holdsBar: true),
              let overlay = cover.members.first
        else {
            PelmetLog.log("livemirror: cover on display \(side.id) can't be built for \(Int(left))..\(Int(right)) (\(why)); picture \(Int(picture.windowFrame.minX))..\(Int(picture.windowFrame.maxX))")
            return false
        }
        let old = side.cover
        side.cover = cover
        side.coverMinX = overlay.windowFrame.minX
        side.coverMaxX = overlay.windowFrame.maxX
        overlay.setClickHook { [weak self, weak side] point in
            guard let self, let side else { return }
            self.clicked(side, at: point)
        }
        side.layerAttached = false
        layoutMirror(side)
        if why != "enter" { PelmetLog.log("livemirror: cover #\(overlay.id) on display \(side.id) \(Int(side.coverMinX))..\(Int(side.coverMaxX)) (\(why))") }
        if coverLifted { overlay.setShown(false) } else { logOrder(overlay, why: "cover \(why)") }
        old?.dismiss()
        return true
    }

    /// The windows a still leaves out: Pelmet's own (the covers) and other
    /// apps' surfaces over the pill's spot (Sconce's notch glass draws its
    /// glyphs over it). The windows list needs a moment to name a window
    /// that just came up.
    private func windowsToExclude(over visual: CGRect, on side: Side) async -> [SCWindow] {
        let me = ProcessInfo.processInfo.processIdentifier
        let wanted = Set(sides.compactMap { $0.cover?.members.first?.windowNumber })
        let foreign = Set(ConcealGhostOverlay.foreignBandWindows(intersecting: visual, bandHeight: side.picture?.windowFrame.height ?? 39).map(\.id))
        var out: [SCWindow] = []
        for attempt in 0..<12 {
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let ordinary = Set(ConcealGhostOverlay.ordinaryAppWindows(content?.windows ?? []).map(\.windowID))
            out = content?.windows.filter { $0.owningApplication?.processID == me || foreign.contains($0.windowID) || ordinary.contains($0.windowID) } ?? []
            if wanted.isSubset(of: Set(out.map { Int($0.windowID) })) {
                if attempt > 0 { PelmetLog.log("livemirror: cover windows listed after \(attempt) retry(ies)") }
                break
            }
            try? await Task.sleep(for: .milliseconds(60))
        }
        return out
    }

    // MARK: The mirror

    /// Reads the pill's tree and brings the mirror up to it: a new still when
    /// the image children changed, the texts redrawn when they did.
    private func apply(_ tree: PillTree, to side: Side, why: String) async {
        let look = tree.look
        if side.look == nil, side.base.contents == nil, let still = kept[side.id] {
            let age = Int(Date().timeIntervalSince(still.at))
            if age < 900, look.change(from: still.look) == nil {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                side.base.contents = still.image
                side.base.contentsGravity = .resize
                CATransaction.commit()
                side.look = still.look
                side.snapTexts = still.texts
                PelmetLog.log("livemirror: still reused — the look is unchanged since \(age)s, no capture")
            }
        }
        var reason: String?
        if let old = side.look, side.base.contents != nil { reason = look.change(from: old) }
        else { reason = "first (\(why))" }
        if reason == nil, side.base.contents != nil, !side.snapping { reason = textTrigger(side, tree) }
        if let reason, !side.snapping {
            side.snapping = true
            if await snapshot(side, tree, reason: reason) { side.look = look }
            side.snapping = false
        }
        side.tree = tree
        side.visual = tree.visual
        layoutMirror(side)
        drawTexts(side, tree, why: why)
    }

    /// The pill's text differs from the one in the still: a reason to take
    /// a new still now, or nil (nothing changed, or the rate limit holds it
    /// back and a trailing snapshot is waiting).
    private func textTrigger(_ side: Side, _ tree: PillTree) -> String? {
        let now = tree.texts.map(\.value)
        guard let was = side.snapTexts, now != was else { return nil }
        let change = "\(was.joined(separator: " ")) → \(now.joined(separator: " "))"
        let interval = Self.textSnapshotInterval
        if let last = textSnapAt[side.id], Date().timeIntervalSince(last) < interval {
            let wait = interval - Date().timeIntervalSince(last)
            PelmetLog.log("livemirror: snapshot skipped — rate limit (text \(change), next in \(Int(wait.rounded(.up)))s)")
            if side.trailing == nil {
                side.trailing = Task { @MainActor [weak self, weak side] in
                    try? await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled, let self, let side else { return }
                    side.trailing = nil
                    await self.refreshPill(side, why: "trailing snapshot")
                }
            }
            return nil
        }
        textSnapAt[side.id] = Date()
        side.trailing?.cancel()
        side.trailing = nil
        return "text changed (\(change))"
    }

    /// One still of the pill, the texts blanked out of it.
    private func snapshot(_ side: Side, _ tree: PillTree, reason: String) async -> Bool {
        let visual = tree.visual
        let started = Date()
        let excluded = await windowsToExclude(over: visual, on: side)
        let filter = SCContentFilter(display: side.scDisplay, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        let local = visual.offsetBy(dx: -side.bounds.minX, dy: -side.bounds.minY)
        config.sourceRect = local
        config.width = max(2, Int((local.width * side.scale).rounded()))
        config.height = max(2, Int((local.height * side.scale).rounded()))
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.shouldBeOpaque = true
        config.ignoreShadowsDisplay = true
        let image: CGImage
        do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) }
        catch {
            PelmetLog.log("livemirror: snapshot on display \(side.id) failed — \(error.localizedDescription)")
            return false
        }
        side.snapshots += 1
        let scale = side.scale
        let rects = tree.texts.map { node in
            CGRect(x: (node.frame.minX - visual.minX) * scale, y: (node.frame.minY - visual.minY) * scale,
                   width: node.frame.width * scale, height: node.frame.height * scale)
        }
        let blanked = Self.blanked(image, rects: rects)
        if let dir = UserDefaults.standard.string(forKey: "pelmet.debug.liveMirrorDump") {
            Self.dump(image, to: "\(dir)/still-\(side.snapshots)-raw.png")
            Self.dump(blanked, to: "\(dir)/still-\(side.snapshots)-blanked.png")
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        side.base.contents = blanked
        side.base.contentsGravity = .resize
        CATransaction.commit()
        let texts = tree.texts.map(\.value)
        side.snapTexts = texts
        kept[side.id] = KeptStill(look: tree.look, image: blanked, at: Date(), texts: texts)
        PelmetLog.log("livemirror: snapshot #\(side.snapshots) — \(reason) [display \(side.id), \(image.width)×\(image.height)px, \(Int(-started.timeIntervalSinceNow * 1000))ms, \(excluded.count) window(s) left out]")
        return true
    }

    nonisolated private static func dump(_ image: CGImage, to path: String) {
        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    /// The still with each rect (pixels, top-left origin) painted over from
    /// the bar above and below it, column by column.
    nonisolated private static func blanked(_ image: CGImage, rects: [CGRect]) -> CGImage {
        let width = image.width, height = image.height
        guard let space = image.colorSpace,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
              let data = context.data
        else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let rowBytes = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: rowBytes * height)
        for rect in rects {
            let x0 = max(0, Int(rect.minX.rounded(.down)) - 1), x1 = min(width, Int(rect.maxX.rounded(.up)) + 1)
            let y0 = max(0, Int(rect.minY.rounded(.down)) - 1), y1 = min(height, Int(rect.maxY.rounded(.up)) + 1)
            let top = max(0, y0 - 2), bottom = min(height - 1, y1 + 1)
            guard x1 > x0, y1 > y0 else { continue }
            for x in x0..<x1 {
                for y in y0..<y1 {
                    let t = y1 > y0 ? Double(y - y0) / Double(max(1, y1 - y0 - 1)) : 0
                    for c in 0..<4 {
                        let a = Double(pixels[top * rowBytes + x * 4 + c]), b = Double(pixels[bottom * rowBytes + x * 4 + c])
                        pixels[y * rowBytes + x * 4 + c] = UInt8(max(0, min(255, a + (b - a) * t)))
                    }
                }
            }
        }
        return context.makeImage() ?? image
    }

    /// The pill's texts, drawn by Dimble at their AX frames. A value that
    /// names a team ("Senators 1") shows its last word when the frame is
    /// the width of that alone.
    private func drawTexts(_ side: Side, _ tree: PillTree, why: String) {
        guard let visual = side.visual else { return }
        let nodes = tree.texts
        CATransaction.begin(); CATransaction.setDisableActions(true)
        while side.textLayers.count > nodes.count { side.textLayers.removeLast().removeFromSuperlayer() }
        while side.textLayers.count < nodes.count {
            let layer = CATextLayer()
            layer.alignmentMode = .center
            layer.truncationMode = .none
            layer.isWrapped = false
            layer.contentsScale = side.scale
            layer.foregroundColor = NSColor.white.cgColor
            side.container.addSublayer(layer)
            side.textLayers.append(layer)
        }
        var shown: [String] = []
        for (node, layer) in zip(nodes, side.textLayers) {
            let size = max(6, node.frame.height / 1.15)
            let font = Self.font(size: size, forDigits: node.value.contains { $0.isNumber } && !node.value.contains(":"))
            let text = Self.displayText(node.value, width: node.frame.width, font: font)
            shown.append(text)
            layer.font = font
            layer.fontSize = size
            layer.string = text
            let lineHeight = ceil(font.ascender - font.descender)
            let relX = node.frame.minX - visual.minX
            let relY = node.frame.midY - visual.minY
            layer.frame = CGRect(x: relX - 6, y: visual.height - relY - lineHeight / 2 + 0.5, width: node.frame.width + 12, height: lineHeight)
        }
        CATransaction.commit()
        if shown != side.texts {
            if !side.texts.isEmpty { PelmetLog.log("livemirror: display \(side.id) text \(side.texts) → \(shown) (seen by \(why))") }
            side.texts = shown
            side.textChangedAt = Date()
        }
    }

    nonisolated private static func font(size: CGFloat, forDigits: Bool) -> NSFont {
        if forDigits {
            let base = NSFont.systemFont(ofSize: size, weight: .bold)
            let condensed = base.fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.width: -0.35]])
            return NSFont(descriptor: condensed, size: size) ?? base
        }
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
    }

    nonisolated private static func displayText(_ value: String, width: CGFloat, font: NSFont) -> String {
        let full = (value as NSString).size(withAttributes: [.font: font]).width
        if full <= width * 1.6 { return value }
        return value.split(separator: " ").last.map(String.init) ?? value
    }

    /// The mirror's container in the cover, its right edge a few points left
    /// of the cover's end (the « sits just past it).
    private func layoutMirror(_ side: Side) {
        guard let overlay = side.cover?.members.first, let visual = side.visual else { return }
        let window = overlay.windowFrame
        let cg = cocoa(visual)
        let global = NSRect(x: side.coverMaxX - Self.gap - visual.width, y: cg.minY, width: visual.width, height: visual.height)
        side.mirrorGlobal = global
        CATransaction.begin(); CATransaction.setDisableActions(true)
        side.container.frame = CGRect(x: global.minX - window.minX, y: global.minY - window.minY, width: visual.width, height: visual.height)
        side.base.frame = side.container.bounds
        CATransaction.commit()
        if !side.layerAttached {
            side.container.removeFromSuperlayer()
            overlay.addLayer(side.container)
            side.layerAttached = true
        }
    }

    // MARK: Watching the pill

    private func startObserving(_ side: Side) {
        guard let pill = side.pill, let agent = NSRunningApplication.runningApplications(withBundleIdentifier: PelmetBundle.agentID).first else { return }
        let observer = PillObserver()
        guard observer.start(pid: agent.processIdentifier) else {
            PelmetLog.log("livemirror: AXObserver on display \(side.id) could not start — polling only")
            return
        }
        observer.onEvent = { [weak self, weak side] _ in
            Task { @MainActor in
                guard let self, let side else { return }
                self.scheduleRefresh(side, why: "ax")
            }
        }
        side.observer = observer
        watchTree(side, observer: observer, pill: pill.element, tree: side.tree)
    }

    private func watchTree(_ side: Side, observer: PillObserver, pill: AXUIElement, tree: PillTree?) {
        let box = ElementBox(list: [pill] + (tree?.nodes.map(\.element) ?? []))
        let count = box.list.count
        let id = side.id
        Task.detached(priority: .utility) {
            observer.watch(box.list)
            PelmetLog.log("livemirror: AXObserver on display \(id) watching \(count) element(s) — \(observer.registration)")
        }
    }

    /// Events come in bursts: one read after a short quiet.
    private func scheduleRefresh(_ side: Side, why: String) {
        side.refresh?.cancel()
        side.refresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled, let self else { return }
            await self.refreshPill(side, why: why)
        }
    }

    private func refreshPill(_ side: Side, why: String) async {
        guard isActive, !exiting, let pill = side.pill else { return }
        let tree = await Task.detached(priority: .userInitiated) { () -> PillTree? in
            PillProbe.readTree(pill.element)
        }.value
        guard let tree else {
            side.misses += 1
            if side.misses == 3 {
                PelmetLog.log("livemirror: pill on display \(side.id) unreadable — looking again")
                side.pill = nil
                side.container.isHidden = true
            }
            return
        }
        side.misses = 0
        side.container.isHidden = false
        // Wider than the cover starts: the pill lies left of it.
        if tree.frame.minX < side.coverMinX + 4, let picture = side.picture {
            let left = max(tree.frame.minX - 12, picture.windowFrame.minX + ConcealGhostOverlay.capturePadding)
            PelmetLog.log("livemirror: re-measure — pill left \(Int(tree.frame.minX)) is outside the cover \(Int(side.coverMinX))")
            buildCover(side, left: left, right: side.coverMaxX, why: "pill left of the cover")
        }
        await apply(tree, to: side, why: why)
        if let observer = side.observer, tree.nodes.count != (side.tree?.nodes.count ?? 0) {
            watchTree(side, observer: observer, pill: pill.element, tree: tree)
        }
    }

    // MARK: Clicks

    private func clicked(_ side: Side, at point: NSPoint) {
        guard let rect = side.mirrorGlobal else {
            PelmetLog.log("livemirror: click at \(Int(point.x)),\(Int(point.y)) on display \(side.id) — no mirror yet, swallowed")
            return
        }
        guard rect.insetBy(dx: -2, dy: -4).contains(point) else {
            PelmetLog.log("livemirror: click at \(Int(point.x)),\(Int(point.y)) on display \(side.id) — outside the mirror (\(Int(rect.minX))..\(Int(rect.maxX))), swallowed")
            return
        }
        let id = side.id
        // The cover was ordered front by the click: back under Sconce at once.
        for ms in [0, 20, 60, 120] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in self?.enforceOrder("click +\(ms)ms") }
        }
        Task { @MainActor in
            let at = Date()
            // The card's state is read from AX on every click, never kept.
            let probe = await Task.detached(priority: .userInitiated) { PillProbe.cardProbe() }.value
            if probe.open {
                // The click is already an outside interaction for the card
                // and collapses it; a press on top interrupts that.
                PelmetLog.log("livemirror: click — card open=true action=close result=the click closes it, no press (display \(id); \(probe.detail))")
                await self.confirmCardClosed(from: at, side: side)
                return
            }
            let result = await self.pressPill("mirror click", side: side)
            PelmetLog.log("livemirror: click — card open=false action=press result=\(result) (display \(id); \(probe.detail))")
            var last = probe
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(100))
                last = await Task.detached(priority: .userInitiated) { PillProbe.cardProbe() }.value
                if last.open {
                    PelmetLog.log("livemirror: card opened \(Int(-at.timeIntervalSinceNow * 1000))ms after the click")
                    return
                }
            }
            PelmetLog.log("livemirror: card did not open within 1.2s of the press — \(last.detail)")
        }
    }

    private func confirmCardClosed(from start: Date, side: Side) async {
        var last = ""
        for _ in 0..<14 {
            try? await Task.sleep(for: .milliseconds(100))
            let probe = await Task.detached(priority: .userInitiated) { PillProbe.cardProbe() }.value
            last = probe.detail
            if !probe.open {
                PelmetLog.log("livemirror: card closed \(Int(-start.timeIntervalSinceNow * 1000))ms after the click (\(probe.detail))")
                return
            }
        }
        PelmetLog.log("livemirror: card still open 1.4s after the click — pressing the pill (\(last))")
        let result = await pressPill("click fallback", side: side)
        PelmetLog.log("livemirror: click — card open=true action=press (fallback) result=\(result)")
    }

    // MARK: Cover order

    private func logOrder(_ overlay: ConcealGhostOverlay, why: String) {
        let below = overlay.orderBelowForeign()
        PelmetLog.log("livemirror: cover order — \(below.map { "below \($0.owner) \($0.id)" } ?? "in front, no foreign surface over the strip") (\(why))")
    }

    /// Every cover shown again ends directly below the foreign surfaces.
    private func setCoversShown(_ shown: Bool, why: String) {
        for side in sides {
            guard let overlay = side.cover?.members.first else { continue }
            overlay.setShown(shown)
            if shown { logOrder(overlay, why: why) }
        }
    }

    /// The window server's order, not ours: a cover that sits above a
    /// foreign surface (a click orders it in front of its level; a strip made
    /// while Sconce's window was being redrawn) goes back below it.
    private func enforceOrder(_ why: String) {
        for line in ConcealGhostOverlay.keepBelowForeign() {
            PelmetLog.log("livemirror: cover order — corrected, \(line) (\(why))")
        }
    }

    /// Covers are checked every 250ms, every 50ms while a transition runs.
    private func startOrderKeeper() {
        guard orderKeeper == nil else { return }
        orderKeeper = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let busy = ConcealGhostOverlay.coverCount > 1 || self.entering || self.exiting || self.handingOver
                if ConcealGhostOverlay.coverCount > 0, !self.coverLifted || ConcealGhostOverlay.coverCount > 1 {
                    self.enforceOrder(busy ? "transition" : "keeper")
                }
                try? await Task.sleep(for: .milliseconds(busy ? 50 : 250))
            }
        }
    }

    /// The backdrop under the cover can't be told from here without a
    /// capture: the Space and the appearance changing are the signals. The
    /// cover is retaken by leaving live mode and entering again, the still
    /// kept: the picture must be of the concealed bar.
    private func backdropMayHaveChanged(_ reason: String) async {
        try? await Task.sleep(for: .milliseconds(600))
        guard isActive, !handingOver, !entering, !exiting else { return }
        PelmetLog.log("livemirror: cover retake — \(reason)")
        await exit("cover retake", keepStills: true)
    }

    /// The « (or the item) asked for a reveal: the cover goes, the real bar
    /// shows; the same again, or a few seconds, and it comes back.
    private func toggleCover(_ why: String) {
        coverLifted.toggle()
        liftedReturn?.cancel()
        PelmetLog.log("livemirror: cover \(coverLifted ? "lifted — the real bar shows" : "back") (\(why))")
        setCoversShown(!coverLifted, why: "cover back (\(why))")
        guard coverLifted else { return }
        liftedReturn = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.liftedCoverReturn))
            guard let self, !Task.isCancelled, self.coverLifted else { return }
            self.toggleCover("\(Int(Self.liftedCoverReturn))s")
        }
    }

    // MARK: Tick

    private func tick() async {
        guard let appState else { return }
        tickCount += 1
        // The « moved (extras came or went, the capture indicator lit or
        // went out): the cover's end follows it.
        if let chevron = appState.chevronWindowFrame, let last = lastChevron,
           abs(chevron.minX - last.minX) > 0.5 || abs(chevron.minY - last.minY) > 0.5 {
            PelmetLog.log("livemirror: re-measure — chevron \(Int(last.minX)) → \(Int(chevron.minX))")
            lastChevron = chevron
            for side in sides {
                buildCover(side, left: side.coverMinX, right: chevronMinX(chevron, on: side) - 1, why: "chevron moved")
            }
        }
        for side in sides {
            // The net is read every 2 s; while the text is moving (a countdown)
            // it is read every tick, so the mirror does not skip a second.
            let textMoving = side.textChangedAt.map { Date().timeIntervalSince($0) < 5 } ?? false
            if side.pill == nil || textMoving || tickCount % Self.fallbackEvery == 0 {
                if side.pill == nil {
                    let copies = await Task.detached(priority: .userInitiated) { PillProbe.copies() }.value
                    if let copy = copies.first(where: { PillProbe.picks($0, in: side.bounds) }) {
                        PelmetLog.log("livemirror: pill found on display \(side.id) at tick")
                        side.pill = copy
                        side.observer?.stop()
                        side.observer = nil
                        await refreshPill(side, why: "found")
                        startObserving(side)
                    }
                } else {
                    await refreshPill(side, why: "poll")
                }
            }
        }
        for side in sides { side.cover?.keepUp(for: Self.coverSafety) }
        if Date().timeIntervalSince(lastSummaryAt) > 10 {
            let span = Int(Date().timeIntervalSince(lastSummaryAt))
            lastSummaryAt = Date()
            for side in sides {
                let counts = side.observer?.drainCounts() ?? [:]
                let events = counts.isEmpty ? "none" : counts.sorted { $0.key < $1.key }.map { "\($0.key.replacingOccurrences(of: "AX", with: "").replacingOccurrences(of: "Notification", with: ""))×\($0.value)" }.joined(separator: " ")
                PelmetLog.log("livemirror: display \(side.id) \(span)s — AX events \(events), snapshots \(side.snapshots) so far, texts \(side.texts)")
            }
        }
    }

    // MARK: Exit

    func exit(_ reason: String, keepStills: Bool = false) async {
        guard let appState, isActive, !exiting else { return }
        exiting = true
        defer { exiting = false }
        let started = Date()
        PelmetLog.log("livemirror: exit — \(reason)")
        liftedReturn?.cancel()
        if !keepStills { kept = [:] }
        // The card goes with the pill.
        if await cardIsOpen() {
            PelmetLog.log("livemirror: card open (exit) — closing it")
            await pressPill("exit")
        }
        if coverLifted {
            coverLifted = false
            setCoversShown(true, why: "exit")
        }
        for side in sides {
            side.refresh?.cancel()
            side.trailing?.cancel()
            side.trailing = nil
            side.observer?.stop()
            side.observer = nil
            PelmetLog.log("livemirror: display \(side.id) \(side.snapshots) snapshot(s) this run")
        }
        // The « slides back and the extras leave: the cover reaches to the
        // concealed « again, where the picture ends.
        for side in sides {
            if let picture = side.picture { buildCover(side, left: side.coverMinX, right: picture.windowFrame.maxX - (side.screen.frame.maxX - primaryMaxX) + (side.screen.frame.maxX - primaryMaxX), why: "exit") }
        }
        await appState.engine.holdLift(false)
        PelmetLog.log("livemirror: assertion back at \(Int(-started.timeIntervalSinceNow * 1000))ms")
        await appState.transitions.endLive(covers: sides.compactMap(\.cover))
        sides = []
        ConcealGhostOverlay.liveModeBlocksCaptures = false
        appState.transitions.liveModeActive = false
        isActive = false
        lastChevron = nil
        PelmetLog.log("livemirror: exit done in \(Int(-started.timeIntervalSinceNow * 1000))ms")
    }
}
