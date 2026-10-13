import CoreGraphics
import Testing
@testable import PelmetCore

@Suite struct StandInMatchTests {
    // The live test's bars, 2026-10-13: the LG active (real buttons), the
    // built-in showing stand-ins. Pelmet's extras bar lists the chevron,
    // Shortcuts and Media in that order, framed where the LG draws them.
    let extras: [CGFloat?] = [5010, 4901, 5048]   // StatusItem, Shortcuts, MediaControls

    @Test func standInsAreNamedByTheirPlaceAmongTheAppsGroups() {
        // Walk order on the built-in: 1563, 1601, 1454.
        #expect(StandInMatch.items(forGroupsAt: [1563, 1601, 1454], itemsAt: extras) == [0, 2, 1])
    }

    @Test func aCountThatDiffersLeavesEveryGroupUnnamed() {
        // One of the app's icons is not on this bar: which one is a guess.
        #expect(StandInMatch.items(forGroupsAt: [1563, 1601], itemsAt: extras) == [nil, nil])
    }

    @Test func anItemWithoutAFrameLeavesEveryGroupUnnamed() {
        #expect(StandInMatch.items(forGroupsAt: [1563, 1601, 1454], itemsAt: [5010, nil, 5048]) == [nil, nil, nil])
    }

    @Test func groupsSharingAnXStayUnnamedAndTheRestAreNamed() {
        // Two phantoms behind the « at one x; the third group is still known.
        #expect(StandInMatch.items(forGroupsAt: [1200, 1200, 1601], itemsAt: extras) == [nil, nil, 2])
    }

    @Test func itemsSharingAnXLeaveTheirGroupsUnnamed() {
        #expect(StandInMatch.items(forGroupsAt: [1454, 1563, 1601], itemsAt: [4901, 4901, 5048]) == [nil, nil, 2])
    }

    @Test func oneGroupOneItem() {
        #expect(StandInMatch.items(forGroupsAt: [1412], itemsAt: [4851]) == [0])
    }
}
