import Testing
@testable import PelmetEngine

@Suite struct EmptyWalkBackoffTests {
    @Test func slowRetriesDoubleFromTwoSecondsToAMinute() {
        var delays: [Duration] = []
        var previous: Duration?
        for _ in 0..<8 {
            let next = EngineTiming.emptyAXSlowRetry(after: previous)
            delays.append(next)
            previous = next
        }
        #expect(delays == [2, 4, 8, 16, 32, 60, 60, 60].map { Duration.seconds($0) })
    }
}
