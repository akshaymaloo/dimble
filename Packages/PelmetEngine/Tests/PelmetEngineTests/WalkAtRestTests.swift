import Foundation
import Testing
@testable import PelmetEngine

@Suite struct WalkAtRestTests {
    let swap = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func aWalkInsideTheReflowIsNotAtRest() {
        // The walk behind a swap, 50–200ms in: AX lists the strip a part
        // at a time (review of N1, 2026-10-13).
        #expect(!EngineTiming.walkAtRest(startedAt: swap.addingTimeInterval(0.1), lastSwapAt: swap))
    }

    @Test func aWalkStartedPastTheReflowIsAtRest() {
        #expect(EngineTiming.walkAtRest(startedAt: swap.addingTimeInterval(EngineTiming.restWalkDelay), lastSwapAt: swap))
        #expect(EngineTiming.walkAtRest(startedAt: swap.addingTimeInterval(5), lastSwapAt: swap))
    }

    @Test func aWalkASwapOvertookIsNotAtRest() {
        // In flight when the swap was issued: it read the bar before it.
        #expect(!EngineTiming.walkAtRest(startedAt: swap.addingTimeInterval(-0.05), lastSwapAt: swap))
    }

    @Test func noSwapYetIsAtRest() {
        #expect(EngineTiming.walkAtRest(startedAt: swap, lastSwapAt: .distantPast))
    }
}
