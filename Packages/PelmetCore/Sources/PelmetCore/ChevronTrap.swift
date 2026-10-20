// ChevronTrap.swift
// Whether macOS has put Pelmet's chevron behind its own « (#81). On a full
// bar the items that don't fit go behind the «, leftmost first, and the
// chevron is the leftmost item drawn (the hidden ones take no width), so it
// goes first and the user loses the control.
//
// Measured on 27.2 with the ballast harness (2026-10-19): a trapped chevron's
// window stays on the bar, parked on the « (window 1014–1056 against a «
// at 1039–1057; 1589–1631 against 1614–1632), so its frame alone can't tell.
// Its window's occlusion loses `.visible`, and the « is on the bar only
// while something is behind it. The walk's overlap test misses a lone
// trapped chevron: its parked frame overlaps nothing.

import CoreGraphics

public enum ChevronTrap {
    /// - iconShown: the chevron's icon is on (with it off it has no width).
    /// - occlusionVisible: the chevron window's occlusion has `.visible`,
    ///   nil without a window.
    /// - window: the chevron window's frame; only its x is read.
    /// - toggle: the «'s AX frame, nil when the bar has none. AX and AppKit
    ///   share x on the main display.
    public static func isTrapped(iconShown: Bool, occlusionVisible: Bool?, window: CGRect?, toggle: CGRect?) -> Bool {
        guard iconShown, occlusionVisible == false, let window, let toggle else { return false }
        // Parked on the «, not merely occluded somewhere else on a bar that
        // has a « for other icons (a full-screen app hiding the bar, a
        // locked screen).
        return window.minX <= toggle.maxX + slack && window.maxX >= toggle.minX - slack
    }

    static let slack: CGFloat = 4

    // MARK: Making room with Pelmet's own extras

    /// What a notched bar keeps clear right of the notch before the « takes
    /// the leftmost item: the chevron drew 27pt from it (ballast 540) and
    /// went behind at 12pt (555), 2026-10-19. The end that fitted, so an
    /// extra brought back never pushes the chevron behind again.
    public static let notchClearance: CGFloat = 27

    /// The room left of a drawn chevron on a notched bar: what an extra
    /// coming back may take without putting the chevron behind the «.
    /// Measured from the bar's left end (`leftEdge`), not the chevron.
    public static func room(leftEdge: CGFloat, notchMaxX: CGFloat) -> CGFloat {
        leftEdge - notchMaxX - notchClearance
    }

    /// The left end of the bar the chevron is on: the chevron, or an icon
    /// the walk reads left of it, right of the notch. An extra comes back
    /// where the agent puts it, at that end as often as in its slot (Users
    /// left the chevron at x=1562, 2026-10-19 22:52:29), and an icon drawn
    /// there takes the room all the same: at room 60 read from the chevron,
    /// MediaControls came back behind a new « with the chevron unmoved
    /// (22:47:38).
    /// - chevronMinX: the chevron window's x.
    /// - frames: the walk's frames on the chevron's bar.
    public static func leftEdge(chevronMinX: CGFloat, frames: [CGRect], notchMaxX: CGFloat) -> CGFloat {
        frames.reduce(chevronMinX) { edge, frame in
            // Wholly left of the notch is the open «, not the bar's end. An
            // icon parked on a « can start left of it (Users at x=1005 on a
            // 1010 notch, 2026-10-20 08:19:14).
            guard frame.width > 0, frame.maxX > notchMaxX + slack else { return edge }
            return min(edge, frame.minX)
        }
    }

    /// Which extra out of the bar comes back, from their widths in the order
    /// they went: the latest that fits in `room`. Nil when none fits, or the
    /// room is less than `shortRoomMargin` past one a return already failed
    /// at (a « came back with it, or the chevron went behind one).
    public static func restorable(widths: [CGFloat], room: CGFloat, failedRoom: CGFloat?) -> Int? {
        if let failedRoom, room < failedRoom + shortRoomMargin { return nil }
        return widths.indices.last { widths[$0] <= room }
    }

    /// How much more room than a failed return the next one needs. The room
    /// moves a few points with nothing joining the bar: AX pads a frame by
    /// up to 2pt, and an icon that draws what it counts (a timer, a network
    /// meter) changes width with its digits. Without it a return failed at
    /// 60 came back at 61 and failed again every 30s (review, 2026-10-20).
    public static let shortRoomMargin: CGFloat = 10
}

/// A room a return failed at, with the icons the bar drew then: it holds for
/// that bar only. An icon that joins or leaves it (an app adding its icon on
/// wake, then quitting) makes another bar, and the room is read afresh.
public struct ShortRoom: Equatable, Sendable {
    public let room: CGFloat
    public let bar: Set<ItemID>

    public init(room: CGFloat, bar: Set<ItemID>) {
        self.room = room
        self.bar = bar
    }

    public func holds(on bar: Set<ItemID>) -> Bool { self.bar == bar }
}

/// The bar read again after an extra came back, at rest only (a reveal, a
/// pass or Apply has a bar of its own): no « on the chevron's bar and it
/// fits; a « twice in a row and it didn't, wherever the agent put it.
public struct RestoreCheck: Sendable {
    public enum Verdict: Equatable, Sendable { case fits, short }

    private var toggleReads = 0

    public init() {}

    /// One read at rest; the verdict once there is one.
    public mutating func read(toggleOnBar: Bool) -> Verdict? {
        guard toggleOnBar else { return .fits }
        toggleReads += 1
        return toggleReads >= 2 ? .short : nil
    }
}
