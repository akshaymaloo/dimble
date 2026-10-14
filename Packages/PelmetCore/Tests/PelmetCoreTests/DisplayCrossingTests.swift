import Testing
@testable import PelmetCore

@Suite struct DisplayCrossingTests {
    let main = "MAIN", side = "SIDE"

    func action(
        from previous: String?, to current: String?, _ behavior: DisplayBehavior,
        launched: Bool = true, revealed: Bool = false
    ) -> DisplayCrossing.Action {
        DisplayCrossing.action(from: previous, to: current, behavior: behavior, launched: launched, revealed: revealed)
    }

    @Test func theFirstSightingOnAnAlwaysShowAllDisplayRevealsOnceLaunched() {
        // As a baseline it revealed nothing until the pointer crossed back
        // (live test, 2026-10-13, after the 20:09 launch).
        #expect(action(from: nil, to: side, .alwaysShowAll) == .reveal)
        // Before the launch's conceal: its own baseline applies the policy.
        #expect(action(from: nil, to: side, .alwaysShowAll, launched: false) == .none)
    }

    @Test func theFirstSightingOnACollapsingDisplayStaysABaseline() {
        // Arming the countdown there concealed the bar on the first move
        // after a reveal.
        #expect(action(from: nil, to: main, .collapse, revealed: true) == .none)
        #expect(action(from: nil, to: main, .collapse, launched: false, revealed: true) == .none)
    }

    @Test func crossingsActAsBefore() {
        #expect(action(from: main, to: side, .alwaysShowAll) == .reveal)
        #expect(action(from: main, to: side, .alwaysShowAll, launched: false) == .reveal)
        #expect(action(from: side, to: main, .collapse, revealed: true) == .leaveBand)
        #expect(action(from: side, to: main, .collapse, revealed: false) == .none)
    }

    @Test func stayingOnADisplayDoesNothing() {
        #expect(action(from: side, to: side, .alwaysShowAll) == .none)
        #expect(action(from: nil, to: nil, .alwaysShowAll) == .none)
    }
}
