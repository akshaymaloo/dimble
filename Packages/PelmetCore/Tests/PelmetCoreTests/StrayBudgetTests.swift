import Testing
@testable import PelmetCore

@Suite struct StrayBudgetTests {
    let a = ItemID.bundleKey("com.a"), b = ItemID.bundleKey("com.b")
    var hidden: Roster { Roster(members: [a: .hidden, b: .hidden]) }

    @Test func twoAttemptsThenItGivesUpOnceAndStaysQuiet() {
        var budget = StrayBudget()
        var verdict = budget.check([a], roster: hidden)
        #expect(verdict.ready == [a])
        budget.spend([a], roster: hidden)
        #expect(budget.check([a], roster: hidden).ready == [a])
        budget.spend([a], roster: hidden)
        verdict = budget.check([a], roster: hidden)
        #expect(verdict.ready.isEmpty && verdict.exhausted == [a] && verdict.newlyExhausted == [a])
        #expect(budget.check([a], roster: hidden).newlyExhausted.isEmpty)
    }

    @Test func eachItemHasItsOwnBudget() {
        var budget = StrayBudget()
        budget.spend([a], roster: hidden)
        budget.spend([a], roster: hidden)
        let verdict = budget.check([a, b], roster: hidden)
        #expect(verdict.ready == [b] && verdict.exhausted == [a])
    }

    @Test func aChangedSectionClearsOnlyThatItem() {
        var budget = StrayBudget()
        budget.spend([a, b], roster: hidden)
        budget.spend([a, b], roster: hidden)
        var moved = hidden
        moved.assign(a, to: .alwaysHidden)
        let verdict = budget.check([a, b], roster: moved)
        #expect(verdict.ready == [a] && verdict.exhausted == [b])
    }

    @Test func nothingElseResets() {
        // A clear bar, a check with other strays, the item missing for a
        // while: none of it wipes what a used.
        var budget = StrayBudget()
        budget.spend([a], roster: hidden)
        budget.spend([a], roster: hidden)
        #expect(budget.check([], roster: hidden).ready.isEmpty)
        #expect(budget.check([b], roster: hidden).ready == [b])
        let verdict = budget.check([a], roster: hidden)
        #expect(verdict.exhausted == [a] && verdict.ready.isEmpty)
    }

    @Test func aSectionChangeMadeWhileNotAStrayStartsFresh() {
        // Vorssaint moved to Visible and placed, moved to Hidden and back
        // while sitting on its side (never a stray in between), placed again,
        // and the same once more: each placement is the first attempt (live
        // test, 2026-10-13 20:14:36, 20:16:28, 20:17:52).
        var visible = hidden
        visible.assign(a, to: .visible)
        var budget = StrayBudget()
        for _ in 0..<3 {
            budget.observe(visible)
            #expect(budget.check([a], roster: visible).ready == [a])
            #expect(budget.used(a, roster: visible) == 0)
            budget.spend([a], roster: visible)
            #expect(budget.check([], roster: visible).ready.isEmpty)
            budget.observe(hidden)
        }
    }

    @Test func observingAnUnchangedSectionKeepsTheBudget() {
        // An app that relaunches on the wrong side changes no section: still
        // not dragged forever.
        var budget = StrayBudget()
        budget.spend([a], roster: hidden)
        budget.spend([a], roster: hidden)
        budget.observe(hidden)
        #expect(budget.check([a], roster: hidden).exhausted == [a])
    }

    @Test func aSectionGoingThereAndBackStartsFresh() {
        var budget = StrayBudget()
        budget.spend([a], roster: hidden)
        budget.spend([a], roster: hidden)
        var away = hidden
        away.assign(a, to: .visible)
        #expect(budget.check([a], roster: away).ready == [a])
        #expect(budget.check([a], roster: hidden).ready == [a])
    }
}
