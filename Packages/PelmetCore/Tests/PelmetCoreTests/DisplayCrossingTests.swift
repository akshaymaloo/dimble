import Testing
@testable import PelmetCore

@Suite struct DisplayCrossingTests {
    let main = "MAIN", side = "SIDE"

    func action(
        from previous: String?, to current: String?, _ behavior: DisplayBehavior,
        launched: Bool = true, revealed: Bool = false, anchored: Bool = false
    ) -> DisplayCrossing.Action {
        DisplayCrossing.action(
            from: previous, to: current, behavior: behavior, launched: launched, revealed: revealed, anchored: anchored
        )
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

    @Test func anAnchoredBarAsksNothingOfAShowAllDisplay() {
        // Its icons are out already: no reveal of its own, and the pointer
        // arriving there leaves a hiding display's reveal (#88).
        #expect(action(from: main, to: side, .alwaysShowAll, anchored: true) == .none)
        #expect(action(from: nil, to: side, .alwaysShowAll, anchored: true) == .none)
        #expect(action(from: main, to: side, .alwaysShowAll, revealed: true, anchored: true) == .leaveBand)
        #expect(action(from: side, to: main, .collapse, revealed: true, anchored: true) == .leaveBand)
    }

    @Test func aShowAllDisplayAnchorsTheBar() {
        var s = SettingsStore()
        s.displayOverrides = [main: .collapse, side: .alwaysShowAll]
        #expect(s.anchorsReveal(connectedDisplayUUIDs: [main, side]))
        #expect(!s.anchorsReveal(connectedDisplayUUIDs: [main]))
        #expect(!s.anchorsReveal(connectedDisplayUUIDs: []))
    }
}
