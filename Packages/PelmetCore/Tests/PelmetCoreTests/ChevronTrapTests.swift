import CoreGraphics
import Testing
@testable import PelmetCore

@Suite struct ChevronTrapTests {
    // Gab's 1800pt built-in, ballast harness, 2026-10-19. AppKit window
    // frames (bottom-left origin), AX « frames (top-left).
    let toggleLeft = CGRect(x: 1039, y: 1, width: 18, height: 30)
    let toggleRight = CGRect(x: 1614, y: 1, width: 18, height: 30)
    let parkedLeft = CGRect(x: 1014, y: 1130, width: 42, height: 39)
    let parkedRight = CGRect(x: 1589, y: 1130, width: 42, height: 39)

    @Test func aChevronParkedOnTheToggleAndOccludedIsTrapped() {
        // 555: the chevron alone behind the «.
        #expect(ChevronTrap.isTrapped(iconShown: true, occlusionVisible: false, window: parkedLeft, toggle: toggleLeft))
        // 570: the chevron and Siri, the « near the clock.
        #expect(ChevronTrap.isTrapped(iconShown: true, occlusionVisible: false, window: parkedRight, toggle: toggleRight))
    }

    @Test func aDrawnChevronIsNotTrapped() {
        // 540: it fits, no « at all.
        let drawn = CGRect(x: 1037, y: 1130, width: 42, height: 39)
        #expect(!ChevronTrap.isTrapped(iconShown: true, occlusionVisible: true, window: drawn, toggle: nil))
        // « expanded: the chevron drawn left of the notch, visible again.
        let expanded = CGRect(x: 728, y: 1130, width: 42, height: 39)
        #expect(!ChevronTrap.isTrapped(iconShown: true, occlusionVisible: true, window: expanded, toggle: toggleLeft))
    }

    @Test func occludedAwayFromTheToggleIsNotTrapped() {
        // A bar with a « for other icons while something else hides the
        // chevron's window where it stands.
        let standing = CGRect(x: 1400, y: 1130, width: 42, height: 39)
        #expect(!ChevronTrap.isTrapped(iconShown: true, occlusionVisible: false, window: standing, toggle: toggleLeft))
    }

    @Test func noToggleNoWindowOrNoIconIsNotTrapped() {
        #expect(!ChevronTrap.isTrapped(iconShown: true, occlusionVisible: false, window: parkedLeft, toggle: nil))
        #expect(!ChevronTrap.isTrapped(iconShown: true, occlusionVisible: nil, window: nil, toggle: toggleLeft))
        #expect(!ChevronTrap.isTrapped(iconShown: false, occlusionVisible: false, window: parkedLeft, toggle: toggleLeft))
    }
}
