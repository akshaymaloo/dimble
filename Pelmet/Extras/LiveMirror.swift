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

nonisolated enum PillProbe {
    static let identifierPrefix = "live-activity-pill-"
    /// Every distinct pill on a display, left to right: macOS shows one pill
    /// per running activity, each with its own AX element (and a copy per bar).
    static func pills(in bounds: CGRect) -> [PillCopy] {
        var out: [PillCopy] = []
        for copy in copies() where bounds.contains(CGPoint(x: copy.frame.midX, y: copy.frame.midY)) {
            // Each bar window holds its own element for the same pill, and
            // while the capture indicator moves things the two can stand a
            // few points apart: one description within 30 pt is one pill.
            if out.contains(where: { $0.name == copy.name && abs($0.frame.minX - copy.frame.minX) < 30 }) { continue }
            out.append(copy)
        }
        return out.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// A pill's identity is its AXDescription ("Sports", "myVW"), the one
    /// thing that names the activity in AX; a second pill with the same
    /// description gets " #2".
    static func keys(of pills: [PillCopy]) -> [String] {
        var counts: [String: Int] = [:]
        return pills.map { pill in
            counts[pill.name, default: 0] += 1
            return counts[pill.name]! == 1 ? pill.name : "\(pill.name) #\(counts[pill.name]!)"
        }
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

    /// The tree in hand still stands: the pill's frame and each text's value
    /// are as they were (three or four reads, against the whole tree's
    /// hundred). A moved or retitled pill takes the full read.
    static func unchanged(_ tree: PillTree, of element: AXUIElement) -> Bool {
        guard CFEqual(tree.pill, element), let frame = frame(of: element),
              abs(frame.minX - tree.frame.minX) < 0.05, abs(frame.minY - tree.frame.minY) < 0.05, abs(frame.width - tree.frame.width) < 0.05
        else { return false }
        for node in tree.texts {
            guard (attribute(node.element, kAXValueAttribute) as? String) == node.value else { return false }
        }
        return true
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

    /// The same read with what it saw: whose card is open (the group's
    /// AXDescription is its pill's, "Sports"), and the agent's windows with
    /// their frames, a star on the one holding the live-activity group.
    static func cardProbe() -> (open: Bool, owners: [String], detail: String) {
        guard let app = agentApp() else { return (false, [], "no agent") }
        AXUIElementSetMessagingTimeout(app, 0.6)
        func owner(_ element: AXUIElement, _ depth: Int) -> String? {
            if (attribute(element, kAXSubroleAttribute) as? String) == "AXLiveActivity" {
                return (attribute(element, kAXDescriptionAttribute) as? String) ?? ""
            }
            guard depth < 4 else { return nil }
            for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                if let found = owner(child, depth + 1) { return found }
            }
            return nil
        }
        var raw: AnyObject?
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw)
        let windows = (raw as? [AXUIElement]) ?? []
        var owners: [String] = []
        var parts: [String] = []
        for window in windows {
            guard let frame = frame(of: window) else { parts.append("?"); continue }
            let who = frame.minY >= 20 ? owner(window, 0) : nil
            if let who { owners.append(who) }
            parts.append("\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))\(who.map { "*\($0)" } ?? "")")
        }
        return (!owners.isEmpty, owners, "ax \(error == .success ? "ok" : "err \(error.rawValue)"), \(windows.count) window(s) [\(parts.joined(separator: "; "))]")
    }

    /// Presses the pill that sits in `bounds`, looked up fresh (the element
    /// in hand may be a copy the agent has since replaced); the one in hand
    /// is the fallback. Returns what happened, for the log, and the fresh copy.
    static func press(in bounds: CGRect, named: String?, kept: AXUIElement?) -> (result: String, fresh: PillCopy?) {
        let fresh = pills(in: bounds).first { named == nil || $0.name == named }
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
        // The pills are the bar windows' own children (app > window > item).
        collect(app, depth: 3, into: &found)
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
    /// Between two mirrors when the real pills' own gap can't be measured.
    private static let pillGap: CGFloat = 8
    private static let coverSafety: TimeInterval = 3600
    private static let liftedCoverReturn: TimeInterval = 10

    /// One real pill's mirror: the still with its texts blanked, and the
    /// texts drawn over it from AX, in a container inside the cover.
    private final class PillMirror {
        let key: String
        var copy: PillCopy
        var tree: PillTree?
        var look: PillTree.Look?
        /// The texts as drawn, and the AX texts as of the last still (a change
        /// in them is what the text-triggered snapshot compares against).
        var texts: [String] = []
        var snapTexts: [String]?
        var textChangedAt: Date?
        /// A changed look waits until two reads half a second apart agree: the
        /// pill slides when the capture indicator lights or goes out, and a
        /// still taken mid-slide has a cut edge.
        var lookCandidate: (look: PillTree.Look, since: Date)?
        var misses = 0
        /// Discovery passes that did not find it (two in a row end it).
        var absent = 0
        /// No room left of the « for it.
        var dropped = false
        let firstSeen = Date()
        let container = CALayer()
        let base = CALayer()
        var textLayers: [CATextLayer] = []
        var attached = false
        /// CG global: the pill's visual; Cocoa global: where its mirror stands.
        var visual: CGRect?
        var global: NSRect?

        init(key: String, copy: PillCopy) {
            self.key = key; self.copy = copy
            container.addSublayer(base)
        }
    }

    /// One display's share of live mode.
    private final class Side {
        let id: CGDirectDisplayID
        let screen: NSScreen
        let scDisplay: SCDisplay
        var picture: ConcealGhostOverlay.BarSnapshot?
        var cover: ConcealGhostOverlay.GhostSet?
        var coverMinX: CGFloat = 0
        var coverMaxX: CGFloat = 0
        /// One mirror per running activity, in the order macOS shows the pills
        /// (left to right).
        var mirrors: [PillMirror] = []
        var needsDiscovery = false
        var droppedNote = ""
        var placedNote = ""
        var snapping = false
        var snapshots = 0
        /// The text last reported as skipped: one line per change, not per read.
        var skippedText = ""
        /// The one trailing snapshot waiting for the rate limit to pass.
        var trailing: Task<Void, Never>?

        init(id: CGDirectDisplayID, screen: NSScreen, scDisplay: SCDisplay) {
            self.id = id; self.screen = screen; self.scDisplay = scDisplay
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
    private var kept: [String: KeptStill] = [:]
    private func keptKey(_ side: Side, _ mirror: PillMirror) -> String { "\(side.id)|\(mirror.key)" }
    /// Drawn graphics (a ring, a bar) usually move with the pill's text. A
    /// text change takes a new still, at most once per interval per display
    /// (a ticking countdown must not keep the capture dot lit); changes inside
    /// the window coalesce into one trailing snapshot. Kept across live mode.
    static let textSnapshotInterval: TimeInterval = 30
    /// How long a changed look must hold still before a new still is taken.
    static let lookSettle: TimeInterval = 0.45
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
            side.mirrors.contains { !$0.dropped && !$0.container.isHidden && ($0.global?.insetBy(dx: -6, dy: -6).contains(point) ?? false) }
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
            side.trailing?.cancel()
            side.trailing = nil
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for mirror in side.mirrors { mirror.container.isHidden = true }
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
                for mirror in side.mirrors { mirror.container.isHidden = mirror.dropped }
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
    /// Presses the real pill `name` (a mirror's own) on `side`, looked up
    /// fresh; no name presses the first mirror's.
    @discardableResult
    private func pressPill(_ why: String, side: Side? = nil, name: String? = nil) async -> String {
        guard let side = side ?? sides.first(where: { !$0.mirrors.isEmpty }) ?? sides.first else { return "no display" }
        let bounds = side.bounds
        let mirror = side.mirrors.first { name == nil || $0.copy.name == name } ?? side.mirrors.first
        let kept = ElementBox(list: mirror.map { [$0.copy.element] } ?? [])
        let wanted = name ?? mirror?.copy.name
        let started = Date()
        let (result, fresh) = await Task.detached(priority: .userInitiated) { PillProbe.press(in: bounds, named: wanted, kept: kept.list.first) }.value
        if let fresh, let mirror { mirror.copy = fresh }
        let text = "\(result) in \(Int(-started.timeIntervalSinceNow * 1000))ms"
        PelmetLog.log("livemirror: card — AX press on the pill \"\(wanted ?? "?")\" (\(why)) → \(text)")
        return text
    }

    private func cardProbe() async -> (open: Bool, owners: [String], detail: String) {
        await Task.detached(priority: .userInitiated) { PillProbe.cardProbe() }.value
    }

    /// Closes the card if it is open. `mouseDismisses`: a click started this,
    /// and the click is already an outside interaction that collapses the
    /// card; a press now would interrupt that collapse and leave it open.
    private func closeCard(why: String, mouseDismisses: Bool) async {
        let probe = await cardProbe()
        guard probe.open else { return }
        let owner = probe.owners.first { !$0.isEmpty }
        let started = Date()
        if mouseDismisses {
            PelmetLog.log("livemirror: card open (\(why)) — the click closes it")
        } else {
            PelmetLog.log("livemirror: card open (\(why)) — closing it")
            await pressPill(why, name: owner)
        }
        for _ in 0..<14 {
            try? await Task.sleep(for: .milliseconds(100))
            if !(await cardProbe()).open {
                PelmetLog.log("livemirror: card closed \(Int(-started.timeIntervalSinceNow * 1000))ms after (\(why))")
                return
            }
        }
        PelmetLog.log("livemirror: card still open 1.4s after (\(why))\(mouseDismisses ? " — pressing the pill" : "")")
        if mouseDismisses { await pressPill(why, name: owner) }
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
        for side in sides { side.cover?.dismiss() }
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
            for side in sides where side.mirrors.isEmpty {
                await discoverPills(side)
                if !side.mirrors.isEmpty { firstPill = firstPill ?? ms() }
            }
            if sides.allSatisfy({ !$0.mirrors.isEmpty }), Date().timeIntervalSince(movedAt) > 0.3 { break }
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
        for side in sides { await refreshSide(side, why: "enter") }
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
        for mirror in side.mirrors { mirror.attached = false }
        layoutMirrors(side)
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

    // MARK: The mirrors

    /// Reads every pill's tree and brings the mirrors up to them: one new still
    /// of all the pills when a look or a text changed, the texts redrawn.
    private func refreshSide(_ side: Side, why: String, full: Bool = true) async {
        guard isActive, !exiting, !side.mirrors.isEmpty else { return }
        let box = ElementBox(list: side.mirrors.map(\.copy.element))
        let before = side.mirrors.map(\.tree)
        let trees = await Task.detached(priority: .userInitiated) { () -> [PillTree?] in
            zip(box.list, before).map { element, was in
                if !full, let was, PillProbe.unchanged(was, of: element) { return was }
                return PillProbe.readTree(element)
            }
        }.value
        guard isActive, !exiting, trees.count == side.mirrors.count else { return }
        var live: [(mirror: PillMirror, tree: PillTree)] = []
        for (mirror, tree) in zip(side.mirrors, trees) {
            guard let tree else {
                mirror.misses += 1
                if mirror.misses == 3 {
                    PelmetLog.log("livemirror: display \(side.id) pill \"\(mirror.key)\" unreadable — looking again")
                    side.needsDiscovery = true
                    mirror.container.isHidden = true
                }
                continue
            }
            mirror.misses = 0
            mirror.tree = tree
            mirror.visual = tree.visual
            live.append((mirror, tree))
        }
        guard !live.isEmpty else { return }
        // Wider than the cover starts: the pill lies left of it.
        if let leftmost = live.map(\.tree.frame.minX).min(), leftmost < side.coverMinX + 4, let picture = side.picture {
            let left = max(leftmost - 12, picture.windowFrame.minX + ConcealGhostOverlay.capturePadding)
            PelmetLog.log("livemirror: re-measure — pill left \(Int(leftmost)) is outside the cover \(Int(side.coverMinX))")
            buildCover(side, left: left, right: side.coverMaxX, why: "pill left of the cover")
        }
        layoutMirrors(side)
        // A kept still of the same look stands in for a capture.
        for (mirror, tree) in live where mirror.look == nil && mirror.base.contents == nil {
            guard let still = kept[keptKey(side, mirror)] else { continue }
            let age = Int(Date().timeIntervalSince(still.at))
            if age < 900, tree.look.change(from: still.look) == nil {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                mirror.base.contents = still.image
                mirror.base.contentsGravity = .resize
                CATransaction.commit()
                mirror.look = still.look
                mirror.snapTexts = still.texts
                PelmetLog.log("livemirror: still reused — \"\(mirror.key)\" is unchanged since \(age)s, no capture")
            }
        }
        var reasons: [String] = []
        var settling = false
        for (mirror, tree) in live {
            let look = tree.look
            if let old = mirror.look, mirror.base.contents != nil {
                if let change = look.change(from: old) {
                    if let candidate = mirror.lookCandidate, candidate.look.change(from: look) == nil {
                        if Date().timeIntervalSince(candidate.since) >= Self.lookSettle { reasons.append(live.count > 1 ? "\(mirror.key) \(change)" : change) }
                        else { settling = true }
                    } else {
                        mirror.lookCandidate = (look, Date())
                        settling = true
                    }
                } else {
                    mirror.lookCandidate = nil
                }
            } else {
                reasons.append(live.count > 1 ? "\(mirror.key) first (\(why))" : "first (\(why))")
            }
        }
        if reasons.isEmpty, !settling, !side.snapping, let text = textTrigger(side, live) { reasons.append(text) }
        if !reasons.isEmpty, !settling, !side.snapping {
            side.snapping = true
            _ = await snapshot(side, live, reason: reasons.joined(separator: "; "))
            side.snapping = false
        }
        for (mirror, tree) in live { drawTexts(mirror, tree, side: side, why: why) }
    }

    /// The pills' texts differ from the ones in the still: a reason to take
    /// a new still now, or nil (nothing changed, or the rate limit holds it
    /// back and a trailing snapshot is waiting). One limit per display, for
    /// every pill together.
    private func textTrigger(_ side: Side, _ live: [(mirror: PillMirror, tree: PillTree)]) -> String? {
        var parts: [String] = []
        for (mirror, tree) in live {
            guard let was = mirror.snapTexts else { continue }
            let now = tree.texts.map(\.value)
            guard now != was else { continue }
            let change = "\(was.joined(separator: " ")) → \(now.joined(separator: " "))"
            parts.append(live.count > 1 ? "\(mirror.key) \(change)" : change)
        }
        guard !parts.isEmpty else { return nil }
        let change = parts.joined(separator: ", ")
        let interval = Self.textSnapshotInterval
        if let last = textSnapAt[side.id], Date().timeIntervalSince(last) < interval {
            let wait = interval - Date().timeIntervalSince(last)
            let signature = live.map { $0.tree.texts.map(\.value).joined(separator: " ") }.joined(separator: "|")
            if side.skippedText != signature {
                side.skippedText = signature
                PelmetLog.log("livemirror: snapshot skipped — rate limit (text \(change), next in \(Int(wait.rounded(.up)))s)")
            }
            if side.trailing == nil {
                side.trailing = Task { @MainActor [weak self, weak side] in
                    try? await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled, let self, let side else { return }
                    side.trailing = nil
                    await self.refreshSide(side, why: "trailing snapshot")
                }
            }
            return nil
        }
        textSnapAt[side.id] = Date()
        side.trailing?.cancel()
        side.trailing = nil
        return "text changed (\(change))"
    }

    /// One still of all the pills on a display (their union, one capture, so
    /// two pills do not double the capture indicator), cropped per pill with
    /// that pill's texts blanked out.
    private func snapshot(_ side: Side, _ entries: [(mirror: PillMirror, tree: PillTree)], reason: String) async -> Bool {
        let shown = entries.filter { !$0.mirror.dropped }
        guard let first = shown.first else { return false }
        let union = shown.dropFirst().reduce(first.tree.visual) { $0.union($1.tree.visual) }
        let started = Date()
        let excluded = await windowsToExclude(over: union, on: side)
        let filter = SCContentFilter(display: side.scDisplay, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        let local = union.offsetBy(dx: -side.bounds.minX, dy: -side.bounds.minY)
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
        let dumpDir = UserDefaults.standard.string(forKey: "pelmet.debug.liveMirrorDump")
        if let dumpDir { Self.dump(image, to: "\(dumpDir)/still-\(side.snapshots)-union.png") }
        textSnapAt[side.id] = Date()
        for (mirror, tree) in shown {
            let v = tree.visual
            let pixels = CGRect(x: (v.minX - union.minX) * scale, y: (v.minY - union.minY) * scale,
                                width: v.width * scale, height: v.height * scale).integral
            guard let crop = image.cropping(to: pixels) else { continue }
            let rects = tree.texts.map { node in
                CGRect(x: (node.frame.minX - union.minX) * scale - pixels.minX, y: (node.frame.minY - union.minY) * scale - pixels.minY,
                       width: node.frame.width * scale, height: node.frame.height * scale)
            }
            let blanked = Self.blanked(crop, rects: rects)
            if let dumpDir { Self.dump(blanked, to: "\(dumpDir)/still-\(side.snapshots)-\(mirror.key)-blanked.png") }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            mirror.base.contents = blanked
            mirror.base.contentsGravity = .resize
            CATransaction.commit()
            let texts = tree.texts.map(\.value)
            mirror.look = tree.look
            mirror.snapTexts = texts
            mirror.lookCandidate = nil
            kept[keptKey(side, mirror)] = KeptStill(look: tree.look, image: blanked, at: Date(), texts: texts)
        }
        PelmetLog.log("livemirror: snapshot #\(side.snapshots) — \(reason) [display \(side.id), \(image.width)×\(image.height)px, \(Int(-started.timeIntervalSinceNow * 1000))ms, \(excluded.count) window(s) left out, \(shown.count) pill(s)]")
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

    /// One pill's texts, drawn by Dimble at their AX frames. A value that
    /// names a team ("Senators 1") shows its last word when the frame is
    /// the width of that alone.
    private func drawTexts(_ mirror: PillMirror, _ tree: PillTree, side: Side, why: String) {
        guard let visual = mirror.visual else { return }
        let nodes = tree.texts
        CATransaction.begin(); CATransaction.setDisableActions(true)
        while mirror.textLayers.count > nodes.count { mirror.textLayers.removeLast().removeFromSuperlayer() }
        while mirror.textLayers.count < nodes.count {
            let layer = CATextLayer()
            layer.alignmentMode = .center
            layer.truncationMode = .none
            layer.isWrapped = false
            layer.contentsScale = side.scale
            layer.foregroundColor = NSColor.white.cgColor
            mirror.container.addSublayer(layer)
            mirror.textLayers.append(layer)
        }
        var shown: [String] = []
        for (node, layer) in zip(nodes, mirror.textLayers) {
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
        if shown != mirror.texts {
            if !mirror.texts.isEmpty { PelmetLog.log("livemirror: display \(side.id) \"\(mirror.key)\" text \(mirror.texts) → \(shown) (seen by \(why))") }
            mirror.texts = shown
            mirror.textChangedAt = Date()
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

    /// The mirrors in the cover, right to left from the « in the order
    /// macOS shows the pills (the rightmost nearest the «), with macOS's own
    /// gap between pills (measured from their AX frames). When they do not
    /// all fit, the most recently started ones stay.
    private func layoutMirrors(_ side: Side) {
        guard let overlay = side.cover?.members.first else { return }
        let window = overlay.windowFrame
        let placed = side.mirrors.filter { $0.visual != nil && $0.misses < 3 }
        var gaps: [CGFloat] = []
        for (a, b) in zip(placed, placed.dropFirst()) {
            let g = b.visual!.minX - a.visual!.maxX
            if g > 0, g < 60 { gaps.append(g) }
        }
        let gap = gaps.isEmpty ? Self.pillGap : gaps.sorted()[gaps.count / 2]
        let right = side.coverMaxX - Self.gap
        let left = side.coverMinX + 4
        func need(_ list: [PillMirror]) -> CGFloat { list.reduce(0) { $0 + $1.visual!.width } + gap * CGFloat(max(0, list.count - 1)) }
        var fit = placed
        var dropped: [PillMirror] = []
        while fit.count > 1, need(fit) > right - left {
            guard let oldest = fit.enumerated().min(by: { ($0.element.firstSeen, $0.offset) < ($1.element.firstSeen, $1.offset) })?.offset else { break }
            dropped.append(fit.remove(at: oldest))
        }
        let note = dropped.map(\.key).sorted().joined(separator: ", ")
        if note != side.droppedNote {
            side.droppedNote = note
            if !note.isEmpty { PelmetLog.log("livemirror: display \(side.id) no room for every mirror (\(Int(right - left))pt) — dropped [\(note)], kept [\(fit.map(\.key).joined(separator: ", "))]") }
        }
        var x = right
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for mirror in placed.reversed() {
            guard let visual = mirror.visual else { continue }
            mirror.dropped = !fit.contains { $0 === mirror }
            if !handingOver { mirror.container.isHidden = mirror.dropped }
            guard !mirror.dropped else { mirror.global = nil; continue }
            x -= visual.width
            let cg = cocoa(visual)
            let global = NSRect(x: x, y: cg.minY, width: visual.width, height: visual.height)
            mirror.global = global
            mirror.container.frame = CGRect(x: global.minX - window.minX, y: global.minY - window.minY, width: visual.width, height: visual.height)
            mirror.base.frame = mirror.container.bounds
            if !mirror.attached {
                mirror.container.removeFromSuperlayer()
                overlay.addLayer(mirror.container)
                mirror.attached = true
            }
            x -= gap
        }
        CATransaction.commit()
        let placedNote = placed.filter { !$0.dropped }.compactMap { m in m.global.map { "\(m.key) \(Int($0.minX))..\(Int($0.maxX))" } }.joined(separator: ", ")
        if placedNote != side.placedNote {
            side.placedNote = placedNote
            PelmetLog.log("livemirror: display \(side.id) mirrors [\(placedNote)] in the cover \(Int(side.coverMinX))..\(Int(side.coverMaxX)), gap \(Int(gap))pt")
        }
    }

    // MARK: Watching the pills

    /// Finds the pills on a display and keeps the mirrors to them: a mirror
    /// per pill, a new one when an activity starts, gone after two passes
    /// that do not find it. The net is read every 2 s.
    private func discoverPills(_ side: Side) async {
        side.needsDiscovery = false
        let bounds = side.bounds
        let found = await Task.detached(priority: .userInitiated) { PillProbe.pills(in: bounds) }.value
        let box = ElementBox(list: found.map(\.element))
        let trees = await Task.detached(priority: .userInitiated) { () -> [PillTree?] in box.list.map { PillProbe.readTree($0) } }.value
        var usable: [PillCopy] = []
        for (copy, tree) in zip(found, trees) {
            if let tree, !tree.texts.isEmpty || !tree.images.isEmpty { usable.append(copy) }
        }
        let keys = PillProbe.keys(of: usable)
        let before = side.mirrors.map(\.key)
        var seen = Set<String>()
        for (copy, key) in zip(usable, keys) {
            seen.insert(key)
            if let mirror = side.mirrors.first(where: { $0.key == key }) {
                mirror.copy = copy
                mirror.absent = 0
            } else {
                side.mirrors.append(PillMirror(key: key, copy: copy))
            }
        }
        for mirror in side.mirrors where !seen.contains(mirror.key) { mirror.absent += 1 }
        for mirror in side.mirrors where mirror.absent >= 2 { mirror.container.removeFromSuperlayer() }
        side.mirrors.removeAll { $0.absent >= 2 }
        side.mirrors.sort { $0.copy.frame.minX < $1.copy.frame.minX }
        let after = side.mirrors.map(\.key)
        if before != after {
            PelmetLog.log("livemirror: pills [\(before.joined(separator: ", "))] → [\(after.joined(separator: ", "))] (display \(side.id))")
            side.droppedNote = ""
            layoutMirrors(side)
        }
    }

    // MARK: Clicks

    private func clicked(_ side: Side, at point: NSPoint) {
        let visible = side.mirrors.filter { !$0.dropped && $0.global != nil }
        guard !visible.isEmpty else {
            PelmetLog.log("livemirror: click at \(Int(point.x)),\(Int(point.y)) on display \(side.id) — no mirror yet, swallowed")
            return
        }
        guard let mirror = visible.first(where: { !$0.container.isHidden && $0.global!.insetBy(dx: -2, dy: -4).contains(point) }) else {
            let span = visible.map { $0.global! }.reduce(visible[0].global!) { $0.union($1) }
            PelmetLog.log("livemirror: click at \(Int(point.x)),\(Int(point.y)) on display \(side.id) — outside the mirrors (\(Int(span.minX))..\(Int(span.maxX))), swallowed")
            return
        }
        let id = side.id
        let name = mirror.copy.name
        // The cover was ordered front by the click: back under Sconce at once.
        for ms in [0, 20, 60, 120] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in self?.enforceOrder("click +\(ms)ms") }
        }
        Task { @MainActor in
            let at = Date()
            // The card's state is read from AX on every click, never kept; the
            // open card's group is named for its pill.
            let probe = await self.cardProbe()
            if probe.open {
                let own = probe.owners.contains(name) || probe.owners.allSatisfy(\.isEmpty)
                if own {
                    // The click is already an outside interaction for the card
                    // and collapses it; a press on top interrupts that.
                    PelmetLog.log("livemirror: click — \"\(mirror.key)\" card open=true action=close result=the click closes it, no press (display \(id); \(probe.detail))")
                    await self.confirmCardClosed(from: at, side: side, name: name)
                    return
                }
                // Another pill's card is open: the click collapses it, then this one opens.
                PelmetLog.log("livemirror: click — \"\(mirror.key)\" while \(probe.owners) is open, action=close it first (the click does), then press")
                var closed = false
                for _ in 0..<14 {
                    try? await Task.sleep(for: .milliseconds(100))
                    if !(await self.cardProbe()).open { closed = true; break }
                }
                if !closed { PelmetLog.log("livemirror: card \(probe.owners) still open 1.4s after — pressing \"\(mirror.key)\" anyway") }
            }
            let result = await self.pressPill("mirror click", side: side, name: name)
            PelmetLog.log("livemirror: click — \"\(mirror.key)\" card open=false action=press result=\(result) (display \(id); \(probe.detail))")
            var last = probe
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(100))
                last = await self.cardProbe()
                if last.owners.contains(name) || (last.open && last.owners.allSatisfy(\.isEmpty)) {
                    PelmetLog.log("livemirror: card \"\(name)\" opened \(Int(-at.timeIntervalSinceNow * 1000))ms after the click")
                    return
                }
            }
            PelmetLog.log("livemirror: card \"\(name)\" did not open within 1.2s of the press — \(last.detail)")
        }
    }

    private func confirmCardClosed(from start: Date, side: Side, name: String) async {
        var last = ""
        for _ in 0..<14 {
            try? await Task.sleep(for: .milliseconds(100))
            let probe = await cardProbe()
            last = probe.detail
            if !probe.open || !probe.owners.contains(name) && !probe.owners.allSatisfy(\.isEmpty) {
                PelmetLog.log("livemirror: card closed \(Int(-start.timeIntervalSinceNow * 1000))ms after the click (\(probe.detail))")
                return
            }
        }
        PelmetLog.log("livemirror: card still open 1.4s after the click — pressing the pill (\(last))")
        let result = await pressPill("click fallback", side: side, name: name)
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

    /// Covers are checked every second, every 50ms while a transition runs.
    private func startOrderKeeper() {
        guard orderKeeper == nil else { return }
        orderKeeper = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let busy = ConcealGhostOverlay.coverCount > 1 || self.entering || self.exiting || self.handingOver
                if ConcealGhostOverlay.coverCount > 0, !self.coverLifted || ConcealGhostOverlay.coverCount > 1 {
                    self.enforceOrder(busy ? "transition" : "keeper")
                }
                try? await Task.sleep(for: .milliseconds(busy ? 50 : 1000))
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
            // The pills are looked for every 2 s (an activity starting or ending),
            // read every 2 s too; while a text moves (a countdown) or a look
            // settles they are read every tick, so the mirror skips no second.
            let now = Date()
            let moving = side.mirrors.contains { ($0.textChangedAt.map { now.timeIntervalSince($0) < 5 } ?? false) || $0.lookCandidate != nil }
            let net = tickCount % Self.fallbackEvery == 0
            var looked = false
            if side.mirrors.isEmpty || side.needsDiscovery || net {
                await discoverPills(side)
                looked = true
            }
            if !side.mirrors.isEmpty, moving || net || looked { await refreshSide(side, why: looked ? "found" : "poll", full: net || looked) }
        }
        for side in sides { side.cover?.keepUp(for: Self.coverSafety) }
        if Date().timeIntervalSince(lastSummaryAt) > 10 {
            let span = Int(Date().timeIntervalSince(lastSummaryAt))
            lastSummaryAt = Date()
            for side in sides {
                PelmetLog.log("livemirror: display \(side.id) \(span)s — snapshots \(side.snapshots) so far, pills \(side.mirrors.map { "\($0.key) \($0.texts)" })")
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
        let open = await cardProbe()
        if open.open {
            PelmetLog.log("livemirror: card open (exit) — closing it")
            await pressPill("exit", name: open.owners.first { !$0.isEmpty })
        }
        if coverLifted {
            coverLifted = false
            setCoversShown(true, why: "exit")
        }
        for side in sides {
            side.trailing?.cancel()
            side.trailing = nil
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
