// LiveMirror.swift
// Live mode (spike, `-pelmet.debug.liveMirror YES`): while a Live Activity
// runs, the real pill shows beside the « and the hidden icons stay hidden.
//
// MenuBarAgent takes the pill off the bar under any hide assertion, so live
// mode holds none: the assertion goes (`engine.holdLift`), the icons it hid
// come back onto the bar, and a picture of the concealed bar, taken just
// before, covers [left limit, «) on every display. The pill's real frame is
// read over AX (MenuBarAgent, subrole AXLiveActivity) and filmed with an
// SCStream at 2 fps, Pelmet's own windows left out, into a layer in the cover
// just left of the «. A click on that layer is forwarded to the real pill as
// an AX press. A click on the « lifts the cover (the real bar, hidden icons
// and pill, shows) and a second one, or ten seconds, puts it back. When the
// activity ends the assertion comes back under the cover, which lifts once
// the bar beneath has settled (`TransitionCoordinator.endLive`).
//
// Every step logs with a `livemirror:` prefix.

import AppKit
import ApplicationServices
import PelmetCore
import PelmetEngine
import QuartzCore
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

nonisolated enum PillProbe {
    static let identifierPrefix = "live-activity-pill-"

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
    static func text(of element: AXUIElement, depth: Int = 2) -> String {
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

// MARK: - The stream

/// One display's film of the pill: an SCStream on a source rect at a low
/// frame rate, handing each frame over as a copied image.
nonisolated final class MirrorStream: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Frame: @unchecked Sendable { let image: CGImage }
    private let queue = DispatchQueue(label: "app.fif7y.Pelmet.livemirror.capture")
    private let lock = NSLock()
    private var stream: SCStream?
    private var lastHash: UInt64 = 0
    private var _frames = 0, _changed = 0
    var onFrame: (@Sendable (Frame, Bool) -> Void)?
    var onStop: (@Sendable (String) -> Void)?

    var counts: (frames: Int, changed: Int) {
        lock.lock(); defer { lock.unlock() }
        return (_frames, _changed)
    }

    func resetCounts() {
        lock.lock(); _frames = 0; _changed = 0; lock.unlock()
    }

    private static func configuration(_ rect: CGRect, scale: CGFloat, fps: Double) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = max(2, Int((rect.width * scale).rounded()))
        config.height = max(2, Int((rect.height * scale).rounded()))
        config.minimumFrameInterval = CMTime(seconds: 1 / fps, preferredTimescale: 600)
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.shouldBeOpaque = true
        config.queueDepth = 3
        return config
    }

    func start(display: SCDisplay, excluding: [SCWindow], rect: CGRect, scale: CGFloat, fps: Double) async throws {
        let filter = SCContentFilter(display: display, excludingWindows: excluding)
        let stream = SCStream(filter: filter, configuration: Self.configuration(rect, scale: scale, fps: fps), delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func retarget(rect: CGRect, scale: CGFloat, fps: Double) async throws {
        try await stream?.updateConfiguration(Self.configuration(rect, scale: scale, fps: fps))
    }

    func exclude(_ windows: [SCWindow], on display: SCDisplay) async throws {
        try await stream?.updateContentFilter(SCContentFilter(display: display, excludingWindows: windows))
    }

    func stop() async {
        let stream = self.stream
        self.stream = nil
        try? await stream?.stopCapture()
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStop?(error.localizedDescription)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let buffer = sampleBuffer.imageBuffer else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachments.first?[.status] as? Int,
           let status = SCFrameStatus(rawValue: raw),
           status != .complete { return }
        guard let (image, hash) = Self.image(from: buffer) else { return }
        lock.lock()
        _frames += 1
        let changed = hash != lastHash
        if changed { _changed += 1; lastHash = hash }
        lock.unlock()
        onFrame?(Frame(image: image), changed)
    }

    /// A copy of the frame (the stream reuses its buffers) and a hash of it.
    private static func image(from buffer: CVPixelBuffer) -> (CGImage, UInt64)? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let data = Data(bytes: base, count: bytesPerRow * height)
        var hash: UInt64 = 14695981039346656037
        data.withUnsafeBytes { raw in
            for byte in raw.bindMemory(to: UInt8.self) { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let space = (CVBufferCopyAttachment(buffer, kCVImageBufferCGColorSpaceKey, nil) as! CGColorSpace?)
            ?? CGColorSpaceCreateDeviceRGB()
        guard let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: space,
            bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)],
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        ) else { return nil }
        return (image, hash)
    }
}

// MARK: - Live mode

@MainActor
final class LiveMirror {
    static let flagKey = "pelmet.debug.liveMirror"
    /// Debug: while true live mode is left (or not entered), for cycling it by hand.
    static let suspendKey = "pelmet.debug.liveMirrorSuspend"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: flagKey) }

    private static let fps = 2.0
    private static let pollInterval = Duration.milliseconds(250)
    /// Points the mirror keeps clear of the « and of the cover's right end.
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
        var stream = MirrorStream()
        let mirror = CALayer()
        var pill: PillCopy?
        var pillFrame: CGRect?
        var lastText = ""
        var textChangedAt: Date?
        var misses = 0
        var coverMinX: CGFloat = 0
        var coverMaxX: CGFloat = 0
        var mirrorGlobal: NSRect?
        var gotFrame = false
        var shown = 0
        var layerAttached = false
        var lastWindowsAt = Date.distantPast

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
    private var screenObserver: NSObjectProtocol?

    init(appState: AppState) { self.appState = appState }

    // MARK: Entry points

    func activitiesChanged(running: Bool) {
        guard Self.enabled else { return }
        if running != wanted { PelmetLog.log("livemirror: activities \(running ? "running" : "none") — wanted \(running)") }
        wanted = running
        if loop == nil { startLoop() }
    }

    /// A reveal asked for while live mode has the bar. The « (and the item)
    /// lift the cover; every other trigger waits for live mode to end.
    func intercepts(reveal reason: RevealReason) -> Bool {
        guard isActive else { return false }
        switch reason {
        case .statusItem, .click, .doubleClick, .hotkey:
            toggleCover("\(reason)")
        default:
            PelmetLog.log("livemirror: reveal(\(reason)) blocked — live mode has the bar")
        }
        return true
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
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let suspended = UserDefaults.standard.bool(forKey: Self.suspendKey)
                let desired = self.wanted && !suspended && Self.enabled
                if self.entering || self.exiting {
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
            await side.stream.stop()
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

        // 1. The streams first: a running capture lights the system's
        // indicator, which moves the bar's cluster a few points left. The
        // picture and the cover's end are taken in that place.
        for side in sides {
            let right = chevronMinX(chevron, on: side)
            let local = CGRect(x: right - side.bounds.minX - 70, y: 0, width: 64, height: 39)
            side.stream.onFrame = { [weak self, weak side] frame, changed in
                Task { @MainActor in
                    guard let self, let side else { return }
                    self.deliver(frame, changed: changed, to: side)
                }
            }
            side.stream.onStop = { why in PelmetLog.log("livemirror: stream stopped — \(why)") }
            do {
                try await side.stream.start(display: side.scDisplay, excluding: [], rect: local, scale: side.scale, fps: Self.fps)
            } catch {
                await abort("stream on display \(side.id) failed: \(error.localizedDescription)")
                return
            }
        }
        let firstBy = Date().addingTimeInterval(0.8)
        while Date() < firstBy, sides.contains(where: { !$0.gotFrame }) { try? await Task.sleep(for: .milliseconds(20)) }
        PelmetLog.log("livemirror: streams up at \(ms())ms, \(fps(sides.filter(\.gotFrame).count, of: sides.count)) first frame(s) in")
        try? await Task.sleep(for: .milliseconds(450))
        let before = chevron
        chevron = appState.chevronWindowFrame ?? chevron
        PelmetLog.log("livemirror: chevron \(Int(before.minX)) → \(Int(chevron.minX)) after the streams (capture indicator)")
        lastChevron = chevron

        // 2. The picture of the concealed bar, each display from its left
        // limit to the «, and the cover over it.
        for side in sides {
            let right = chevronMinX(chevron, on: side) - 1
            let left = coverLeft(for: side, right: right)
            let shift = side.screen.frame.maxX - primaryMaxX
            let rect = CGRect(x: left - shift, y: 0, width: right - left, height: 40)
            side.picture = await ConcealGhostOverlay.snapshotSet(of: rect, displays: [side.id], liveMirror: true).first
            guard side.picture != nil else { await abort("no picture of display \(side.id)"); return }
            PelmetLog.log("livemirror: display \(side.id) picture \(Int(side.picture!.windowFrame.minX))..\(Int(side.picture!.windowFrame.maxX)) (wanted \(Int(left))..\(Int(right)))")
            guard buildCover(side, left: left, right: right, why: "enter") else { await abort("cover won't crop on display \(side.id)"); return }
        }
        ConcealGhostOverlay.liveModeBlocksCaptures = true
        await excludeOwnWindows()
        PelmetLog.log("livemirror: covers up at \(ms())ms — \(sides.map { "d\($0.id) \(Int($0.coverMinX))..\(Int($0.coverMaxX))" }.joined(separator: ", "))")

        // 3. The assertion goes: the hidden icons come back under the cover,
        // the pill after them.
        await appState.engine.holdLift(true)
        let dropped = ms()
        PelmetLog.log("livemirror: assertion down at \(dropped)ms")

        // 4. The pill.
        let pillBy = Date().addingTimeInterval(4)
        var firstWalk: Int?
        while Date() < pillBy {
            let copies = await Task.detached(priority: .userInitiated) { PillProbe.copies() }.value
            if !copies.isEmpty {
                firstWalk = ms()
                for copy in copies {
                    let mid = CGPoint(x: copy.frame.midX, y: copy.frame.midY)
                    if let side = sides.first(where: { $0.bounds.contains(mid) }), side.pill == nil { await attach(side, copy) }
                }
                if sides.allSatisfy({ $0.pill != nil }) { break }
            }
            try? await Task.sleep(for: .milliseconds(60))
        }
        PelmetLog.log("livemirror: live at \(ms())ms (assertion down \(dropped)ms, pill \(firstWalk.map { "\($0)ms" } ?? "never seen"))")
        lastSummaryAt = Date()
    }

    private func fps(_ n: Int, of total: Int) -> String { "\(n)/\(total)" }

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
        if coverLifted { overlay.setShown(false) }
        side.layerAttached = false
        layoutMirror(side)
        if why != "enter" { PelmetLog.log("livemirror: cover #\(overlay.id) on display \(side.id) \(Int(side.coverMinX))..\(Int(side.coverMaxX)) (\(why))") }
        old?.dismiss()
        return true
    }

    /// Pelmet's own windows, the covers included, left out of every stream.
    /// The windows list needs a moment to name a window that just came up.
    private func excludeOwnWindows() async {
        let me = ProcessInfo.processInfo.processIdentifier
        let wanted = Set(sides.compactMap { $0.cover?.members.first?.windowNumber })
        var own: [SCWindow] = []
        for attempt in 0..<12 {
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            own = content?.windows.filter { $0.owningApplication?.processID == me } ?? []
            let have = Set(own.map { Int($0.windowID) })
            if wanted.isSubset(of: have) {
                if attempt > 0 { PelmetLog.log("livemirror: cover windows listed after \(attempt) retry(ies)") }
                break
            }
            try? await Task.sleep(for: .milliseconds(60))
        }
        for side in sides {
            do { try await side.stream.exclude(own, on: side.scDisplay) }
            catch { PelmetLog.log("livemirror: exclusion on display \(side.id) failed — \(error.localizedDescription)") }
        }
        PelmetLog.log("livemirror: \(own.count) own window(s) left out of the streams")
    }

    // MARK: Pill and mirror

    private func attach(_ side: Side, _ copy: PillCopy) async {
        side.pill = copy
        side.pillFrame = copy.frame
        side.lastText = copy.text
        side.misses = 0
        PelmetLog.log("livemirror: pill on display \(side.id) \(copy.name) frame \(Int(copy.frame.minX)),\(Int(copy.frame.minY)) \(Int(copy.frame.width))×\(Int(copy.frame.height)) text '\(copy.text)'")
        // Wider than the cover starts: the pill lies left of it.
        if copy.frame.minX < side.coverMinX + 4, let chevron = lastChevron, let picture = side.picture {
            let right = chevronMinX(chevron, on: side) - 1
            let left = max(copy.frame.minX - 12, picture.windowFrame.minX + ConcealGhostOverlay.capturePadding)
            PelmetLog.log("livemirror: re-measure — pill left \(Int(copy.frame.minX)) is outside the cover \(Int(side.coverMinX))")
            buildCover(side, left: left, right: right, why: "pill left of the cover")
            await excludeOwnWindows()
        }
        await retarget(side)
        layoutMirror(side)
    }

    private func retarget(_ side: Side) async {
        guard let frame = side.pillFrame else { return }
        let local = frame.offsetBy(dx: -side.bounds.minX, dy: -side.bounds.minY)
        do {
            try await side.stream.retarget(rect: local, scale: side.scale, fps: Self.fps)
            PelmetLog.log("livemirror: stream on display \(side.id) retargeted to \(Int(local.minX)),\(Int(local.minY)) \(Int(local.width))×\(Int(local.height)) @\(Int(Self.fps))fps")
        } catch {
            PelmetLog.log("livemirror: retarget on display \(side.id) failed — \(error.localizedDescription)")
        }
    }

    /// The mirror's layer in the cover, its right edge a few points left of
    /// the cover's end (the « sits just past it).
    private func layoutMirror(_ side: Side) {
        guard let overlay = side.cover?.members.first, let pill = side.pillFrame else { return }
        let size = pill.size
        let window = overlay.windowFrame
        let cg = cocoa(pill)
        let global = NSRect(x: side.coverMaxX - Self.gap - size.width, y: cg.minY, width: size.width, height: size.height)
        side.mirrorGlobal = global
        CATransaction.begin(); CATransaction.setDisableActions(true)
        side.mirror.contentsGravity = .resize
        side.mirror.magnificationFilter = .linear
        side.mirror.contentsScale = side.scale
        side.mirror.frame = CGRect(x: global.minX - window.minX, y: global.minY - window.minY, width: size.width, height: size.height)
        CATransaction.commit()
        if !side.layerAttached {
            side.mirror.removeFromSuperlayer()
            overlay.addLayer(side.mirror)
            side.layerAttached = true
        }
    }

    /// A frame from the stream. Frames of the keepalive rect, or of an
    /// earlier pill size, are skipped.
    private func deliver(_ frame: MirrorStream.Frame, changed: Bool, to side: Side) {
        side.gotFrame = true
        guard let pill = side.pillFrame, isActive else { return }
        let wantW = Int((pill.width * side.scale).rounded()), wantH = Int((pill.height * side.scale).rounded())
        guard abs(frame.image.width - wantW) <= 2, abs(frame.image.height - wantH) <= 2 else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        side.mirror.contents = frame.image
        side.mirror.isHidden = false
        CATransaction.commit()
        side.shown += 1
        if changed, let at = side.textChangedAt, Date().timeIntervalSince(at) < 4 {
            PelmetLog.log("livemirror: display \(side.id) mirror changed \(Int(Date().timeIntervalSince(at) * 1000))ms after the AX text did")
            side.textChangedAt = nil
        }
    }

    // MARK: Clicks

    private func clicked(_ side: Side, at point: NSPoint) {
        guard let rect = side.mirrorGlobal else {
            PelmetLog.log("livemirror: click at \(Int(point.x)),\(Int(point.y)) on display \(side.id) — no mirror yet, swallowed")
            return
        }
        guard rect.insetBy(dx: -2, dy: -4).contains(point), let pill = side.pill else {
            PelmetLog.log("livemirror: click at \(Int(point.x)),\(Int(point.y)) on display \(side.id) — outside the mirror (\(Int(rect.minX))..\(Int(rect.maxX))), swallowed")
            return
        }
        let id = side.id
        let element = pill.element
        let at = Date()
        PelmetLog.log("livemirror: click on the mirror (display \(id)) — pressing the real pill")
        Task.detached(priority: .userInitiated) {
            nonisolated(unsafe) let el = element
            let result = AXUIElementPerformAction(el, kAXPressAction as CFString)
            PelmetLog.log("livemirror: AX press on display \(id) → \(result == .success ? "success" : "error \(result.rawValue)") in \(Int(-at.timeIntervalSinceNow * 1000))ms")
        }
    }

    /// The « (or the item) asked for a reveal: the cover goes, the real bar
    /// shows; the same again, or a few seconds, and it comes back.
    private func toggleCover(_ why: String) {
        coverLifted.toggle()
        liftedReturn?.cancel()
        PelmetLog.log("livemirror: cover \(coverLifted ? "lifted — the real bar shows" : "back") (\(why))")
        for side in sides { side.cover?.members.first?.setShown(!coverLifted) }
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
        // The « moved (the cluster shifted, a reflow): the cover's right end follows.
        if let chevron = appState.chevronWindowFrame, let last = lastChevron,
           abs(chevron.minX - last.minX) > 0.5 || abs(chevron.minY - last.minY) > 0.5 {
            PelmetLog.log("livemirror: re-measure — chevron \(Int(last.minX)) → \(Int(chevron.minX))")
            lastChevron = chevron
            for side in sides {
                let right = chevronMinX(chevron, on: side) - 1
                buildCover(side, left: side.coverMinX, right: right, why: "chevron moved")
            }
            await excludeOwnWindows()
        }
        for side in sides {
            guard let pill = side.pill else {
                // Not seen yet (or lost): one walk per tick.
                let copies = await Task.detached(priority: .userInitiated) { PillProbe.copies() }.value
                if let copy = copies.first(where: { side.bounds.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }) {
                    PelmetLog.log("livemirror: pill found on display \(side.id) at tick")
                    await attach(side, copy)
                }
                continue
            }
            let element = pill.element
            let read = await Task.detached(priority: .userInitiated) { () -> (CGRect, String)? in
                nonisolated(unsafe) let el = element
                return PillProbe.read(el).map { ($0.frame, $0.text) }
            }.value
            guard let (frame, text) = read else {
                side.misses += 1
                if side.misses == 3 {
                    PelmetLog.log("livemirror: pill on display \(side.id) unreadable — looking again")
                    side.pill = nil
                    side.mirror.isHidden = true
                }
                continue
            }
            side.misses = 0
            if text != side.lastText {
                PelmetLog.log("livemirror: display \(side.id) pill text '\(side.lastText)' → '\(text)'")
                side.lastText = text
                side.textChangedAt = Date()
            }
            if let old = side.pillFrame, abs(frame.minX - old.minX) > 0.5 || abs(frame.width - old.width) > 0.5 || abs(frame.minY - old.minY) > 0.5 {
                PelmetLog.log("livemirror: re-measure — pill on display \(side.id) \(Int(old.minX))+\(Int(old.width)) → \(Int(frame.minX))+\(Int(frame.width))")
                side.pillFrame = frame
                if frame.minX < side.coverMinX + 4, let chevron = lastChevron, let picture = side.picture {
                    let right = chevronMinX(chevron, on: side) - 1
                    let left = max(frame.minX - 12, picture.windowFrame.minX + ConcealGhostOverlay.capturePadding)
                    buildCover(side, left: left, right: right, why: "pill grew left")
                    await excludeOwnWindows()
                }
                await retarget(side)
                layoutMirror(side)
            }
        }
        for side in sides { side.cover?.keepUp(for: Self.coverSafety) }
        if Date().timeIntervalSince(lastSummaryAt) > 10 {
            let span = Date().timeIntervalSince(lastSummaryAt)
            lastSummaryAt = Date()
            for side in sides {
                let counts = side.stream.counts
                side.stream.resetCounts()
                PelmetLog.log("livemirror: display \(side.id) capture \(counts.frames) frame(s) in \(Int(span))s (\(counts.changed) changed), \(side.shown) shown, pill \(side.pillFrame.map { "\(Int($0.minX))+\(Int($0.width))" } ?? "none")")
                side.shown = 0
            }
        }
    }

    // MARK: Exit

    func exit(_ reason: String) async {
        guard let appState, isActive, !exiting else { return }
        exiting = true
        defer { exiting = false }
        let started = Date()
        PelmetLog.log("livemirror: exit — \(reason)")
        liftedReturn?.cancel()
        if coverLifted {
            coverLifted = false
            for side in sides { side.cover?.members.first?.setShown(true) }
        }
        for side in sides {
            let counts = side.stream.counts
            PelmetLog.log("livemirror: display \(side.id) last \(counts.frames) frame(s), \(counts.changed) changed")
            await side.stream.stop()
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
