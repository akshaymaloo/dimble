import Foundation
import Testing
@testable import PelmetEngine

@Suite struct EmptyWalkBackoffTests {
    /// The delays of `count` slow retries, the first `emptyFor` seconds into
    /// the run and each later one that delay after the one before.
    func delays(_ count: Int, from emptyFor: TimeInterval) -> [Duration] {
        var delays: [Duration] = []
        var previous: Duration?
        var elapsed = emptyFor
        for _ in 0..<count {
            let next = EngineTiming.emptyAXSlowRetry(after: previous, emptyFor: elapsed)
            delays.append(next)
            previous = next
            elapsed += Double(next.components.seconds)
        }
        return delays
    }

    @Test func slowRetriesStayAtTwoSecondsForTheFirstTwoMinutes() {
        // A launch that reads empty for 40s is retried every 2s throughout.
        #expect(delays(20, from: 3) == Array(repeating: .seconds(2), count: 20))
    }

    @Test func pastTwoMinutesTheyDoubleToAMinute() {
        #expect(delays(8, from: 120) == [2, 4, 8, 16, 32, 60, 60, 60].map { Duration.seconds($0) })
        // A run that starts flat backs off once it crosses the window.
        let crossing = delays(70, from: 3)
        #expect(crossing.prefix(58).allSatisfy { $0 == .seconds(2) })
        #expect(crossing.suffix(3) == [.seconds(60), .seconds(60), .seconds(60)])
    }
}
