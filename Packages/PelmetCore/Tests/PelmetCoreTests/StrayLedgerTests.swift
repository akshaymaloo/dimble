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

    @Test func aDropAfterOurOwnMoveWithNoLookBetweenIsActionable() {
        // Vorssaint dropped to Hidden on the right, our pass put it on the
        // left, and it was dropped back to Visible before the next look:
        // section and side changed together, the side by us (live test,
        // 2026-10-13 21:14:08).
        var ledger = StrayLedger()
        ledger.observe([look(a, .right, .visible)])
        ledger.observe([look(a, .right, .hidden)], strays: [a])
        #expect(ledger.actionable([a]) == [a])
        let byHand = ledger.observe([look(a, .left, .visible)], strays: [a], ownMoves: [a])
        #expect(byHand.isEmpty)
        #expect(ledger.actionable([a]) == [a])
        // Without our move it is an adoption, as before.
        var adopted = StrayLedger()
        adopted.observe([look(a, .right, .hidden)], strays: [a])
        adopted.observe([look(a, .left, .visible)], strays: [a])
        #expect(adopted.actionable([a]).isEmpty)
    }

    @Test func aDropIntoAConcealedSectionIsActionable() {
        // Vorssaint dropped from Visible into a concealed Hidden: the look
        // after the drop has it off the bar, and 36s later the remembered
        // frame puts it back on the right, still concealed (live test,
        // 2026-10-13 21:42:52 → 21:43:30).
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var ledger = StrayLedger()
        ledger.observe([look(a, .right, .visible)], now: t0)
        ledger.observe([.init(id: a, side: nil, section: .hidden, pid: 100, concealed: true)], now: t0 + 2)
        #expect(ledger.standing(of: a) == .actionable)
        ledger.observe([.init(id: a, side: .right, section: .hidden, pid: 100, concealed: true)], strays: [a], now: t0 + 38)
        #expect(ledger.actionable([a]) == [a])
        // Off the bar but not concealed (another display): the window holds.
        var away = StrayLedger()
        away.observe([look(a, .right, .visible)], now: t0)
        away.observe([look(a, nil, .hidden)], now: t0 + 2)
        away.observe([look(a, .right, .hidden)], strays: [a], now: t0 + 38)
        #expect(away.actionable([a]).isEmpty)
        // No frame while concealed, framed at a reveal minutes later: the
        // reveal's look starts the window over.
        var late = StrayLedger()
        late.observe([look(a, .right, .visible)], now: t0)
        late.observe([.init(id: a, side: nil, section: .hidden, pid: 100, concealed: true)], now: t0 + 2)
        late.observe([look(a, .right, .hidden)], strays: [a], now: t0 + 300)
        #expect(late.actionable([a]) == [a])
    }

    @Test func aDropOutOfAConcealedSectionIsActionable() {
        // Never framed while concealed, dropped into Visible: it comes on
        // the bar left of the chevron with its section changed, no hand.
        var ledger = StrayLedger()
        ledger.observe([.init(id: a, side: nil, section: .hidden, pid: 100, concealed: true)])
        ledger.observe([look(a, .left, .visible)], strays: [a])
        #expect(ledger.actionable([a]) == [a])
    }

    @Test func whyNotMovedNamesTheReason() {
        var ledger = StrayLedger()
        ledger.observe([look(a, .left, .hidden), look(b, .left, .hidden)])
        // a flips by hand; b changes section and side together (adopted).
        ledger.observe([look(a, .right, .hidden), look(b, .right, .visible)], strays: [a])
        #expect(ledger.whyNotMoved(a, exhausted: []) == "by hand")
        #expect(ledger.whyNotMoved(b, exhausted: []) == "other (nothing explains it)")
        #expect(ledger.whyNotMoved(b, exhausted: [b]) == "out of attempts")
        #expect(ledger.whyNotMoved(ItemID.bundleKey("com.c"), exhausted: []) == "other (never seen)")
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

    @Test func aStrayMetOnlyConcealedIsNewlySeenAtItsFirstReveal() {
        // Battery in Always Hidden: concealed since launch, right of the
        // chevron at the first reveal (2026-10-20). No hand reached it.
        let hid = StrayLedger.Sighting(id: a, side: nil, section: .alwaysHidden, pid: 100, concealed: true)
        var ledger = StrayLedger()
        ledger.observe([hid])
        ledger.observe([hid])
        ledger.observe([look(a, .right, .alwaysHidden)], strays: [a])
        #expect(ledger.actionable([a]) == [a])
        // Concealed again, framed where the reveal saw it: still explained,
        // for the grouper, which only moves from a concealed bar.
        ledger.observe([.init(id: a, side: .right, section: .alwaysHidden, pid: 100, concealed: true)], strays: [a])
        #expect(ledger.actionable([a]) == [a])
        // Out in place once: a later wrong side is no first look.
        var seen = StrayLedger()
        seen.observe([hid])
        seen.observe([look(a, .left, .alwaysHidden)])
        seen.observe([hid])
        seen.observe([look(a, .right, .alwaysHidden)], strays: [a])
        #expect(seen.actionable([a]).isEmpty)
        // Its side changed while concealed (a frame from a reveal no look
        // saw, a hand drag in it maybe): left alone.
        var unseen = StrayLedger()
        unseen.observe([hid])
        unseen.observe([.init(id: a, side: .right, section: .alwaysHidden, pid: 100, concealed: true)], strays: [a])
        unseen.observe([look(a, .right, .alwaysHidden)], strays: [a])
        #expect(unseen.actionable([a]).isEmpty)
        // Remembered left while concealed, out on the right: a hover's
        // ⌘-drag BarAdoption missed, by hand (review, 2026-10-20).
        var dragged = StrayLedger()
        dragged.observe([.init(id: a, side: .left, section: .hidden, pid: 100, concealed: true)])
        dragged.observe([look(a, .right, .hidden)], strays: [a])
        #expect(dragged.standing(of: a) == .byHand)
        // Out with no place on the primary bar, then dropped on its wrong
        // side: a hand from another display, left alone.
        var away = StrayLedger()
        away.observe([hid])
        away.observe([look(a, nil, .alwaysHidden)])
        away.observe([look(a, .right, .alwaysHidden)], strays: [a])
        #expect(away.actionable([a]).isEmpty)
    }
}
