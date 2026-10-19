// ChevronHosting.swift
// Whether Pelmet's chevron is still on the bar after the displays changed
// (#26). Closing a MacBook Pro's lid with external displays attached and
// opening it on the built-in alone left the chevron's status item on no bar
// at all: the walk named no chevron, its own window sat on no screen, and
// only a relaunch brought it back (cpierce's log, 2026-10-17 12:11 and
// 2026-10-19 07:51). Pure: the app asks after a wake, an unlock or a display
// change, and re-hosts the item on `.rehost`.
//
// Either sign of life counts as hosted: a chevron the walk names anywhere
// (parked offscreen or behind a full bar included) is left to the paths that
// already handle those, and re-hosting is bounded by `budget`.

import CoreGraphics
import Foundation

public enum ChevronHosting {
    public enum Verdict: Equatable, Sendable {
        case hosted
        case rehost
        /// Can't tell yet, or mustn't try again yet: the reason, for the log.
        case wait(String)
    }

    /// At most this many re-hosts per `budgetWindow`: a chevron macOS keeps
    /// dropping is left as is rather than re-hosted on every unlock.
    public static let budget = 2
    public static let budgetWindow: TimeInterval = 600

    /// - drawn: the chevron button's window frame (AppKit space), nil when
    ///   it has none.
    /// - screens: every screen's frame, in the same space.
    /// - walkedItems: items the last walk named. Zero is a locked screen or
    ///   a bar not read yet, never proof the chevron is gone.
    /// - walkedChevron: the walk named the chevron, wherever it sits.
    /// - recentRehosts: re-hosts inside `budgetWindow`.
    public static func verdict(
        drawn: CGRect?, screens: [CGRect], walkedItems: Int, walkedChevron: Bool, recentRehosts: Int
    ) -> Verdict {
        if walkedChevron || drawn.map({ isOnABar($0, screens: screens) }) == true { return .hosted }
        guard walkedItems > 0 else { return .wait("the walk named nothing (locked screen or bar not read yet)") }
        guard recentRehosts < budget else {
            return .wait("re-hosted \(recentRehosts)× in the last \(Int(budgetWindow / 60)) min, left as is")
        }
        return .rehost
    }

    /// The window sits in a screen's menu bar: its middle on that screen and
    /// its bottom inside the top band (AppKit's origin is bottom-left).
    public static func isOnABar(_ frame: CGRect, screens: [CGRect]) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        let mid = CGPoint(x: frame.midX, y: frame.midY)
        return screens.contains { $0.contains(mid) && frame.minY >= $0.maxY - MenuBarGeometry.bandBottomLimit }
    }
}
