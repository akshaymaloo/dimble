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
}
