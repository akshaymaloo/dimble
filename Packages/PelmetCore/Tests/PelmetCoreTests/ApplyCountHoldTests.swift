import Testing
@testable import PelmetCore

@Suite struct ApplyCountHoldTests {
    let t0 = ContinuousClock.now
    func at(_ ms: Int) -> ContinuousClock.Instant { t0 + .milliseconds(ms) }

    @Test func aDropToZeroIsHeldThenShownIfItStillReadsZero() {
        var hold = ApplyCountHold(hold: .milliseconds(300))
        #expect(hold.feed(1, editsPending: true, now: at(0)) == 1)
        // The reveal's settle reads 0: the button keeps its 1.
        #expect(hold.feed(0, editsPending: true, now: at(10)) == 1)
        #expect(hold.isHolding && hold.due == at(310))
        // Reads inside the hold change nothing, and do not push it out.
        #expect(hold.feed(0, editsPending: true, now: at(200)) == 1)
        #expect(hold.due == at(310))
        // Still 0 at the end: shown.
        #expect(hold.feed(0, editsPending: true, now: at(310)) == 0)
        #expect(!hold.isHolding)
    }

    @Test func aHoldIsCancelledWhenTheCountComesBack() {
        var hold = ApplyCountHold(hold: .milliseconds(300))
        hold.feed(1, editsPending: true, now: at(0))
        hold.feed(0, editsPending: true, now: at(10))
        // The walk explaining the reveal lands 126ms later (live test,
        // 2026-10-13 21:13:26.838).
        #expect(hold.feed(1, editsPending: true, now: at(136)) == 1)
        #expect(!hold.isHolding)
        // A later dip starts a hold of its own.
        #expect(hold.feed(0, editsPending: true, now: at(400)) == 1)
        #expect(hold.due == at(700))
    }

    @Test func emptyEditsShowTheCountAtOnce() {
        var hold = ApplyCountHold(hold: .milliseconds(300))
        hold.feed(2, editsPending: true, now: at(0))
        hold.feed(0, editsPending: true, now: at(10))
        // Apply, Discard or a settle cleared the edits mid-hold: no stale 2.
        #expect(hold.feed(0, editsPending: false, now: at(20)) == 0)
        #expect(!hold.isHolding)
        // With no edits a drop to 0 is never held.
        hold.feed(1, editsPending: false, now: at(30))
        #expect(hold.feed(0, editsPending: false, now: at(40)) == 0)
    }

    @Test func risesAndDropsToAnotherNumberShowAtOnce() {
        var hold = ApplyCountHold(hold: .milliseconds(300))
        #expect(hold.feed(0, editsPending: true, now: at(0)) == 0)
        #expect(hold.feed(2, editsPending: true, now: at(10)) == 2)
        #expect(hold.feed(1, editsPending: true, now: at(20)) == 1)
        #expect(!hold.isHolding)
    }
}
