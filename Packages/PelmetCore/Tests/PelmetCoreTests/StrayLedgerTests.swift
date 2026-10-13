import Foundation
import Testing
@testable import PelmetCore

@Suite struct StrayLedgerTests {
    let a = ItemID.bundleKey("com.a"), b = ItemID.bundleKey("com.b")
    let chevron = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.StatusItem")

    func look(_ id: ItemID, _ side: StrayLedger.Side?, _ section: Section, pid: Int32? = 100) -> StrayLedger.Sighting {
        .init(id: id, side: side, section: section, pid: pid)
    }

    @Test func sideOfReadsTheBarAroundTheChevron() {
        let bar = [a, chevron, b]
        #expect(StrayLedger.side(of: a, in: bar, chevron: chevron) == .left)
        #expect(StrayLedger.side(of: b, in: bar, chevron: chevron) == .right)
        #expect(StrayLedger.side(of: chevron, in: bar, chevron: chevron) == nil)
        #expect(StrayLedger.side(of: a, in: bar, chevron: nil) == nil)
    }

    @Test func aNewlySeenStrayIsActionable() {
        var ledger = StrayLedger()
        ledger.observe([look(a, .right, .hidden)], strays: [a])
        #expect(ledger.actionable([a]) == [a])
    }

    @Test func anIconInPlaceIsSettled() {
        var ledger = StrayLedger()
        ledger.observe([look(a, .left, .hidden)])
        #expect(ledger.standing(of: a) == .settled)
    }

    @Test func aRelaunchIsActionableAgain() {
        var ledger = StrayLedger()
        ledger.observe([look(a, .left, .hidden, pid: 1)])
        ledger.observe([look(a, .left, .hidden, pid: 1)])
        // In place and settled until the app comes back as a new process.
        ledger.observe([look(a, .right, .hidden, pid: 2)], strays: [a])
        #expect(ledger.actionable([a]) == [a])
    }

    @Test func aRelaunchMetOffTheBarIsKeptUntilALookPlacesIt() {
        var ledger = StrayLedger()
        ledger.observe([look(a, .left, .hidden, pid: 1)])
        // Back as a new process, not framed yet: no side, no settling.
        ledger.observe([look(a, nil, .hidden, pid: 2)])
        #expect(ledger.standing(of: a) == .actionable)
        // Framed on the wrong side by the same process: still explained.
        ledger.observe([look(a, .right, .hidden, pid: 2)], strays: [a])
        #expect(ledger.actionable([a]) == [a])
        // In place: settled.
        var inPlace = StrayLedger()
        inPlace.observe([look(a, .left, .hidden, pid: 1)])
        inPlace.observe([look(a, nil, .hidden, pid: 2)])
        inPlace.observe([look(a, .left, .hidden, pid: 2)])
        #expect(inPlace.standing(of: a) == .settled)
    }

    @Test func aRelaunchMetOffTheBarLapsesWhenFramedLongAfter() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var ledger = StrayLedger()
        ledger.observe([look(a, .left, .hidden, pid: 1)], now: t0)
        ledger.observe([look(a, nil, .hidden, pid: 2)], now: t0 + 1)
        // Hours on another display, then dragged by hand to the wrong side.
        ledger.observe([look(a, nil, .hidden, pid: 2)], now: t0 + 3600)
        ledger.observe([look(a, .right, .hidden, pid: 2)], strays: [a], now: t0 + 7200)
        #expect(ledger.actionable([a]).isEmpty)
        // No look in between: the same.
        var quiet = StrayLedger()
        quiet.observe([look(a, .left, .hidden, pid: 1)], now: t0)
        quiet.observe([look(a, nil, .hidden, pid: 2)], now: t0 + 1)
        quiet.observe([look(a, .right, .hidden, pid: 2)], strays: [a], now: t0 + 7200)
        #expect(quiet.actionable([a]).isEmpty)
        // Framed inside the window: still explained.
        var prompt = StrayLedger()
        prompt.observe([look(a, .left, .hidden, pid: 1)], now: t0)
        prompt.observe([look(a, nil, .hidden, pid: 2)], now: t0 + 1)
        prompt.observe([look(a, .right, .hidden, pid: 2)], strays: [a], now: t0 + 20)
        #expect(prompt.actionable([a]) == [a])
    }

    @Test func aDropAcrossSectionsIsActionableWhileTheSideStays() {
        var ledger = StrayLedger()
        ledger.observe([look(a, .left, .hidden)])
        ledger.observe([look(a, .left, .visible)], strays: [a])
        #expect(ledger.actionable([a]) == [a])
        // Still a stray at the next look: stays actionable until resolved.
        ledger.observe([look(a, .left, .visible)], strays: [a])
        #expect(ledger.actionable([a]) == [a])
    }

    @Test func aSideFlipByHandIsExemptAndReported() {
        var ledger = StrayLedger()
        ledger.observe([look(a, .left, .hidden)])
        let byHand = ledger.observe([look(a, .right, .hidden)], strays: [a])
        #expect(byHand == [a])
        #expect(ledger.actionable([a]).isEmpty)
        #expect(ledger.standing(of: a) == .byHand)
        // Quiet and exempt on the following looks.
        #expect(ledger.observe([look(a, .right, .hidden)], strays: [a]).isEmpty)
        #expect(ledger.actionable([a]).isEmpty)
    }

    @Test func aFlipOfOurOwnMoveIsOurs() {
        var ledger = StrayLedger()
        ledger.observe([look(a, .right, .hidden)], strays: [a])
        let byHand = ledger.observe([look(a, .left, .hidden)], ownMoves: [a])
        #expect(byHand.isEmpty)
        #expect(ledger.standing(of: a) == .settled)
    }

    @Test func aHandPlacedIconIsActionableAgainWhenItsSectionChanges() {
        var ledger = StrayLedger()
        ledger.observe([look(a, .left, .hidden)])
        ledger.observe([look(a, .right, .hidden)], strays: [a])
        ledger.observe([look(a, .right, .visible)])
        // A drop back to Hidden with the side steady is an editor drop.
        ledger.observe([look(a, .right, .hidden)], strays: [a])
        #expect(ledger.actionable([a]) == [a])
    }

    @Test func aSectionAndSideChangingTogetherIsAdoptionNotAStray() {
        var ledger = StrayLedger()
        ledger.observe([look(a, .left, .hidden)])
        ledger.observe([look(a, .right, .visible)])
        #expect(ledger.standing(of: a) == .settled)
        #expect(ledger.actionable([a]).isEmpty)
    }

    @Test func anIconThatLeftTheBarIsNewlySeenWhenItReturns() {
        var ledger = StrayLedger()
        ledger.observe([look(a, .right, .hidden), look(b, .left, .hidden)])
        ledger.observe([look(b, .left, .hidden)])
        ledger.observe([look(a, .right, .hidden), look(b, .left, .hidden)], strays: [a])
        #expect(ledger.actionable([a]) == [a])
    }

    @Test func aDropFromAnotherDisplayIsLeftWhereItLands() {
        // In place, off to the other display, back on the wrong side with no
        // adoption (nothing identified the drop): not a flip, not new, and
        // nothing explains it, so it stays.
        var ledger = StrayLedger()
        ledger.observe([look(a, .left, .hidden)])
        ledger.observe([look(a, nil, .hidden)])
        ledger.observe([look(a, .right, .hidden)], strays: [a])
        #expect(ledger.actionable([a]).isEmpty)
    }

    @Test func aStrayMetOffTheBarAndFramedLaterIsLeftAlone() {
        var ledger = StrayLedger()
        ledger.observe([look(a, nil, .hidden)])
        ledger.observe([look(a, .right, .hidden)], strays: [a])
        #expect(ledger.actionable([a]).isEmpty)
    }
}
