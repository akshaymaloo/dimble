// ClockTimersTests.swift
// Fixtures follow mobiletimerd's `Timers` lines from macOS 27.2 (2026-10-29,
// a 2 min Clock timer paused, resumed, rung and dismissed, and one
// cancelled), ids and times as logged.

import Foundation
import Testing
@testable import PelmetCore

struct ClockTimersTests {
    static let id = "8F6CFB89-63D1-41E7-88F7-9181C0D61EB8"
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// The start, verbatim.
    static let added = "<MTTimerDurationManager: 0x782b0a4c80> didAddTimers (\n    \"<MTMutableTimer:0x782b2004d0 TimerID: 8F6CFB89-63D1-41E7-88F7-9181C0D61EB8, Title: , state:Running, duration:120, firedDate: (null), dismissedDate: (null), sound: <MTSound:0x782b24de00 toneID: system:Radial, mediaItemID: (null), vibeID: (null), volume: (null), siriContext: (null)>, timerContext: (null)>\"\n)"

    /// The ring, verbatim.
    static let rang = "<MTTimerDurationManager: 0x782b0a4c80> didUpdateTimers fromTimers: (\n    \"<MTMutableTimer:0x782b2004d0 TimerID: 8F6CFB89-63D1-41E7-88F7-9181C0D61EB8, Title: , state:Running, duration:120, firedDate: (null), dismissedDate: (null), sound: <MTSound:0x782b24c5a0 toneID: system:Radial, mediaItemID: (null), vibeID: (null), volume: (null), siriContext: (null)>, timerContext: (null)>\"\n) toTimers: (\n    \"<MTMutableTimer:0x782b200690 TimerID: 8F6CFB89-63D1-41E7-88F7-9181C0D61EB8, Title: , state:Stopped, duration:120, firedDate: 2026-10-29 14:31:08 +0000, dismissedDate: (null), sound: <MTSound:0x782b24c5a0 toneID: system:Radial, mediaItemID: (null), vibeID: (null), volume: (null), siriContext: (null)>, timerContext: (null)>\"\n)"

    /// A change from `from` to `to`, shaped like the logged ones.
    static func update(_ id: String = id, from: String, to: String, fired: String = "(null)", dismissed: String = "(null)") -> String {
        func timer(_ state: String, _ fired: String, _ dismissed: String) -> String {
            "    \"<MTMutableTimer:0x782b200850 TimerID: \(id), Title: , state:\(state), duration:120, firedDate: \(fired), dismissedDate: \(dismissed), sound: <MTSound:0x782b24d770 toneID: system:Radial, mediaItemID: (null), vibeID: (null), volume: (null), siriContext: (null)>, timerContext: (null)>\"\n"
        }
        return "<MTTimerDurationManager: 0x782b0a4c80> didUpdateTimers fromTimers: (\n" + timer(from, "(null)", "(null)")
            + ") toTimers: (\n" + timer(to, fired, dismissed) + ")"
    }

    @Test func aStartEndsItsDurationLater() {
        var clock = ClockTimers()
        let changed = clock.read(Self.added, at: Self.t0)
        #expect(changed)
        #expect(clock.current == .running(ends: Self.t0.addingTimeInterval(120)))
    }

    @Test func aPauseKeepsWhatWasLeftAndAResumeEndsThatMuchLater() {
        var clock = ClockTimers()
        clock.read(Self.added, at: Self.t0)
        clock.read(Self.update(from: "Running", to: "Paused"), at: Self.t0.addingTimeInterval(20))
        #expect(clock.current == .paused(left: 100))
        clock.read(Self.update(from: "Paused", to: "Running"), at: Self.t0.addingTimeInterval(26))
        #expect(clock.current == .running(ends: Self.t0.addingTimeInterval(126)))
    }

    @Test func itRingsThenADismissEndsIt() {
        var clock = ClockTimers()
        clock.read(Self.added, at: Self.t0)
        clock.read(Self.rang, at: Self.t0.addingTimeInterval(120))
        #expect(clock.current == .rang)
        let dismissed = clock.read(Self.update(from: "Stopped", to: "Stopped",
                                               fired: "2026-10-29 14:31:08 +0000", dismissed: "2026-10-29 14:31:14 +0000"),
                                   at: Self.t0.addingTimeInterval(126))
        #expect(dismissed)
        #expect(clock.current == nil)
    }

    @Test func aCancelEndsIt() {
        var clock = ClockTimers()
        clock.read(Self.added, at: Self.t0)
        clock.read(Self.update(from: "Running", to: "Stopped"), at: Self.t0.addingTimeInterval(10))
        #expect(clock.current == nil)
    }

    @Test func presetsAndTimersStartedBeforeTheWindowAreNotFollowed() {
        var clock = ClockTimers()
        let preset = clock.read(Self.update("E597CBFF-0000-4000-8000-000000000000", from: "Stopped", to: "Stopped"), at: Self.t0)
        let unknown = clock.read(Self.update(from: "Paused", to: "Running"), at: Self.t0)
        #expect([preset, unknown] == [false, false])
        #expect(clock.current == nil)
    }

    @Test func theBarShowsARingFirstThenTheOneEndingFirst() {
        var clock = ClockTimers()
        let other = "93DD29CC-038D-4109-8A1C-22C855019D8D"
        clock.read(Self.added, at: Self.t0)
        clock.read(Self.added.replacingOccurrences(of: Self.id, with: other), at: Self.t0.addingTimeInterval(-60))
        #expect(clock.current == .running(ends: Self.t0.addingTimeInterval(60)))
        clock.read(Self.rang, at: Self.t0.addingTimeInterval(120))
        #expect(clock.current == .rang)
    }
}
