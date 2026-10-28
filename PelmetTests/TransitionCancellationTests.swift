import AppKit
import Testing
@testable import Pelmet

@MainActor
struct TransitionCancellationTests {
    @Test func cancelledPrecaptureDoesNotSpinUntilTheQuietDeadline() async {
        let appState = AppState()
        let clock = ContinuousClock()
        let task = Task { @MainActor in
            let start = clock.now
            await appState.waitUntilQuiesced(interval: .infinity, deadline: 2, poll: .milliseconds(30))
            return start.duration(to: clock.now)
        }
        task.cancel()
        #expect(await task.value < .seconds(1))
    }

    @Test func cancellationInterruptsAQuietPollAlreadyAsleep() async {
        let appState = AppState()
        let clock = ContinuousClock()
        let task = Task { @MainActor in
            await appState.waitUntilQuiesced(interval: .infinity, deadline: 2, poll: .seconds(1))
        }
        try? await Task.sleep(for: .milliseconds(50))
        let start = clock.now
        task.cancel()
        await task.value
        #expect(start.duration(to: clock.now) < .seconds(1))
    }

    @Test func anUncancelledQuietWaitStillHonorsItsDeadline() async {
        let appState = AppState()
        let clock = ContinuousClock()
        let start = clock.now
        await appState.waitUntilQuiesced(interval: .infinity, deadline: 0.05, poll: .milliseconds(10))
        #expect(start.duration(to: clock.now) >= .milliseconds(50))
    }

    @Test func aQuietEngineDoesNotWaitForTheDeadline() async {
        let appState = AppState()
        let clock = ContinuousClock()
        let start = clock.now
        await appState.waitUntilQuiesced(interval: 0, deadline: 2, poll: .seconds(1))
        #expect(start.duration(to: clock.now) < .seconds(1))
    }

    @Test func cancelledCaptureDoesNotWaitForAMenuOrRequestScreenAccess() async {
        let previous = ConcealGhostOverlay.menuClosedAt
        defer { ConcealGhostOverlay.menuClosedAt = previous }
        ConcealGhostOverlay.menuClosedAt = Date()
        let task = Task { @MainActor in
            await ConcealGhostOverlay.snapshotSet(of: CGRect(x: 0, y: 0, width: 100, height: 24))
        }
        task.cancel()
        #expect(await task.value.isEmpty)
    }
}
