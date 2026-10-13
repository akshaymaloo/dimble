import CoreGraphics
import Testing
@testable import PelmetCore

@Suite struct StandInMatchTests {
    // The live test's bars, 2026-10-13: the LG active (real buttons), the
    // built-in showing stand-ins. Pelmet's extras bar lists the chevron,
    // Shortcuts and Media in that order, framed where the LG draws them;
    // every group is 38pt wide, every item 24pt.
    let extras: [CGRect?] = [Self.item(5010), Self.item(4901), Self.item(5048)]   // StatusItem, Shortcuts, MediaControls

    static func item(_ x: CGFloat, width: CGFloat = 24) -> CGRect { CGRect(x: x, y: 2, width: width, height: 24) }
    func groups(_ xs: [CGFloat], width: CGFloat = 38) -> [CGRect] { xs.map { CGRect(x: $0, y: 0, width: width, height: 39) } }

    @Test func standInsAreNamedByTheirPlaceAmongTheAppsGroups() {
        // Walk order on the built-in: 1563, 1601, 1454.
        #expect(StandInMatch.items(forGroups: groups([1563, 1601, 1454]), items: extras) == [0, 2, 1])
    }

    @Test func widthGapsThatDisagreeLeaveEveryGroupUnnamed() {
        // The middle group is 18pt wider than its item, the others 14pt:
        // the pairing is not the bar's.
        var framed = groups([1454, 1563, 1601])
        framed[1].size.width = 42
        #expect(StandInMatch.items(forGroups: framed, items: extras) == [nil, nil, nil])
        // Within the tolerance it is one padding.
        framed[1].size.width = 40
        #expect(StandInMatch.items(forGroups: framed, items: extras) == [1, 0, 2])
    }

    @Test func aCountThatDiffersLeavesEveryGroupUnnamed() {
        // One of the app's icons is not on this bar: which one is a guess.
        #expect(StandInMatch.items(forGroups: groups([1563, 1601]), items: extras) == [nil, nil])
    }

    @Test func anItemWithoutAFrameLeavesEveryGroupUnnamed() {
        #expect(StandInMatch.items(
            forGroups: groups([1563, 1601, 1454]), items: [Self.item(5010), nil, Self.item(5048)]
        ) == [nil, nil, nil])
    }

    @Test func groupsSharingAnXStayUnnamedAndTheRestAreNamed() {
        // Two phantoms behind the « at one x; the third group is still known.
        #expect(StandInMatch.items(forGroups: groups([1200, 1200, 1601]), items: extras) == [nil, nil, 2])
    }

    @Test func itemsSharingAnXLeaveTheirGroupsUnnamed() {
        #expect(StandInMatch.items(
            forGroups: groups([1454, 1563, 1601]), items: [Self.item(4901), Self.item(4901), Self.item(5048)]
        ) == [nil, nil, 2])
    }

    @Test func oneGroupOneItem() {
        #expect(StandInMatch.items(forGroups: groups([1412], width: 42), items: [Self.item(4851, width: 44)]) == [0])
    }
}
