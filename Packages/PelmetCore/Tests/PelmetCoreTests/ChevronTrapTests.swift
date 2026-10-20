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

    @Test func roomIsMeasuredFromTheNotchClearance() {
        // Notch's right edge at 1010; the chevron drew at 1037 (540).
        #expect(ChevronTrap.room(leftEdge: 1037, notchMaxX: 1010) == 0)
        #expect(ChevronTrap.room(leftEdge: 1079, notchMaxX: 1010) == 42)
    }

    @Test func theLeftEdgeIsTheLeftmostIconRightOfTheNotch() {
        // The chevron alone at the left end (22:47:20, x=1097).
        let right = [CGRect(x: 1139, y: 0, width: 42, height: 37), CGRect(x: 1181, y: 0, width: 480, height: 37)]
        #expect(ChevronTrap.leftEdge(chevronMinX: 1097, frames: right, notchMaxX: 1010) == 1097)
        // An icon drawn left of it takes the room: 60pt read from the
        // chevron, 18 from the icon.
        let stray = right + [CGRect(x: 1055, y: 0, width: 42, height: 37)]
        let edge = ChevronTrap.leftEdge(chevronMinX: 1097, frames: stray, notchMaxX: 1010)
        #expect(edge == 1055)
        #expect(ChevronTrap.room(leftEdge: edge, notchMaxX: 1010) == 18)
        #expect(ChevronTrap.restorable(widths: [42], room: 18, failedRoom: nil) == nil)
        // An icon parked on a « leaves no room at all, even one that starts
        // left of the notch's edge (2026-10-20 08:19:14).
        let parked = right + [CGRect(x: 1005, y: 0, width: 42, height: 37)]
        #expect(ChevronTrap.room(leftEdge: ChevronTrap.leftEdge(chevronMinX: 1097, frames: parked, notchMaxX: 1010),
                                 notchMaxX: 1010) < 0)
    }

    @Test func theOpenToggleAndEmptyFramesAreNotTheLeftEdge() {
        // The « open: its icons drawn left of the notch.
        let open = [CGRect(x: 682, y: 0, width: 42, height: 37), CGRect(x: 724, y: 0, width: 42, height: 37)]
        #expect(ChevronTrap.leftEdge(chevronMinX: 1097, frames: open, notchMaxX: 1010) == 1097)
        #expect(ChevronTrap.leftEdge(chevronMinX: 1097, frames: [CGRect(x: 1040, y: 0, width: 0, height: 37)],
                                     notchMaxX: 1010) == 1097)
    }

    @Test func theLatestExtraThatFitsComesBack() {
        let widths: [CGFloat] = [42, 573, 42]
        #expect(ChevronTrap.restorable(widths: widths, room: 41, failedRoom: nil) == nil)
        #expect(ChevronTrap.restorable(widths: widths, room: 42, failedRoom: nil) == 2)
        #expect(ChevronTrap.restorable(widths: [42, 573], room: 100, failedRoom: nil) == 0)
        #expect(ChevronTrap.restorable(widths: [42, 573], room: 600, failedRoom: nil) == 1)
        #expect(ChevronTrap.restorable(widths: [], room: 600, failedRoom: nil) == nil)
    }

    @Test func noReturnUntilThereIsMoreRoomThanAtAFailedOne() {
        #expect(ChevronTrap.restorable(widths: [42], room: 60, failedRoom: 60) == nil)
        #expect(ChevronTrap.restorable(widths: [42], room: 50, failedRoom: 60) == nil)
        #expect(ChevronTrap.restorable(widths: [42], room: 61, failedRoom: 60) == 0)
    }
}
