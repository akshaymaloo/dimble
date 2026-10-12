// PanelInsertionLine.swift
// Where a tile dragged up onto the menu bar would land. macOS can't open a
// live gap in the real bar, so a thin vertical line is drawn in the gap
// between two Visible icons instead: a borderless window just above the bar's
// level that takes no mouse events (docs/PANEL-PLAN.md §9 D1, reorder in the
// panel, Gab 2026-10-12).

import AppKit

@MainActor
final class PanelInsertionLine {
    static let width: CGFloat = 2
    /// An icon's height, centred, so it reads as a line between two icons and
    /// not as a seam in the bar (the bar's height less 3pt a side read too tall).
    private static let height: CGFloat = 16

    private let window: NSPanel

    /// `appearance` is the panel's, so the line reads in the same mode.
    init(appearance: NSAppearance?) {
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 20),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        // The status items sit at the status bar's level; one above them.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.appearance = appearance
        window.contentView = LineView()
        window.alphaValue = 0
    }

    /// Centred on `x`, a screen x, across `band`, the bar's rectangle.
    func show(at x: CGFloat, over band: NSRect) {
        let height = min(Self.height, band.height)
        let frame = NSRect(
            x: (x - Self.width / 2).rounded(), y: (band.midY - height / 2).rounded(),
            width: Self.width, height: height)
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        fade(to: 1)
    }

    /// The pointer left the bar, or the drag ended.
    func hide() {
        fade(to: 0)
    }

    /// The drag is over: the line goes with it.
    func close() {
        window.orderOut(nil)
        window.alphaValue = 0
    }

    private func fade(to alpha: CGFloat) {
        guard window.alphaValue != alpha else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = alpha
        }
    }

    /// A rounded stroke in the label colour, which follows the appearance.
    private final class LineView: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }

        required init?(coder: NSCoder) { nil }

        override var wantsUpdateLayer: Bool { true }

        override func updateLayer() {
            layer?.backgroundColor = NSColor.labelColor.cgColor
            layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        }

        override func layout() {
            super.layout()
            needsDisplay = true
        }
    }
}
