import Foundation
import Testing
@testable import PelmetCore

@Suite struct BundlelessMarkTests {
    // #103: ChatGPT Classic's helper, running since before Pelmet launched,
    // read live once by the walk before the first converge.
    @Test func aSettledHostMarksOnOneReading() {
        let step = BundlelessMark.step(marked: false, bundleless: true, streak: 0, hostAge: 600)
        #expect(step.flips)
        #expect(step.streak == 0)
    }

    // Sconce mid-relaunch, 2026-09-14: its new pid read bundle-less for 75ms.
    @Test func aBrandNewHostStillTakesThreeReadings() {
        var streak = 0
        for reading in 1...BundlelessMark.confirmations {
            let step = BundlelessMark.step(marked: false, bundleless: true, streak: streak, hostAge: 0.2)
            #expect(step.flips == (reading == BundlelessMark.confirmations))
            streak = step.streak
        }
        #expect(streak == 0)
    }

    @Test func anUnknownAgeTakesThreeReadings() {
        let first = BundlelessMark.step(marked: false, bundleless: true, streak: 0, hostAge: nil)
        #expect(!first.flips)
        #expect(first.streak == 1)
        let third = BundlelessMark.step(marked: false, bundleless: true, streak: 2, hostAge: nil)
        #expect(third.flips)
    }

    @Test func theAgeLineIsInclusive() {
        #expect(BundlelessMark.step(marked: false, bundleless: true, streak: 0, hostAge: BundlelessMark.settledHostAge).flips)
        #expect(!BundlelessMark.step(marked: false, bundleless: true, streak: 0, hostAge: BundlelessMark.settledHostAge - 0.1).flips)
    }

    // The "fix the app" recovery: a host that reads fine again is unmarked
    // after the full run, however long it has run.
    @Test func unmarkingAlwaysTakesThreeReadings() {
        let first = BundlelessMark.step(marked: true, bundleless: false, streak: 0, hostAge: 600)
        #expect(!first.flips)
        #expect(first.streak == 1)
        #expect(!BundlelessMark.step(marked: true, bundleless: false, streak: 1, hostAge: 600).flips)
        #expect(BundlelessMark.step(marked: true, bundleless: false, streak: 2, hostAge: 600).flips)
    }

    @Test func aReadingThatAgreesClearsTheStreak() {
        #expect(BundlelessMark.step(marked: false, bundleless: false, streak: 2, hostAge: nil) == (false, 0))
        #expect(BundlelessMark.step(marked: true, bundleless: true, streak: 2, hostAge: 600) == (false, 0))
    }
}
