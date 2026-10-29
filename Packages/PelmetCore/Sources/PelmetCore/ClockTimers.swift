// ClockTimers.swift
// The Clock app's timers as mobiletimerd narrates them. Their state sits
// behind the private `com.apple.private.mobiletimerd` entitlement (probed
// 2026-09-15), but the daemon logs every change in the clear at the default
// level (macOS 27.2, read 2026-10-29 off a start, pause, resume, ring,
// dismiss and cancel):
//
//   start   "<MTTimerDurationManager: 0x...> didAddTimers (
//              "<MTMutableTimer:0x... TimerID: <UUID>, Title: , state:Running,
//              duration:120, firedDate: (null), dismissedDate: (null), ...>")"
//   change  "... didUpdateTimers fromTimers: ( <before> ) toTimers: ( <now> )"
//
// States are Running, Paused and Stopped. A cancel stops with no firedDate,
// a ring stops with one and no dismissedDate, a dismiss sets dismissedDate.
// No end is logged in a fixed format (the trigger lines print a localized
// date), so it's kept from the lines' own times: a start ends `duration`
// later, a pause keeps what was left, a resume ends that much later. Off a
// 2 min run with a pause, that came within 40 ms of the Clock's own ring.
// Pure string work so the shape of a real line can be pinned in a test.

import Foundation

/// The Clock app's timers, as far as mobiletimerd's log tells.
public struct ClockTimers: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case running(ends: Date)
        case paused(left: TimeInterval)
        /// Rang; waits for a dismiss (in the Clock app or its banner).
        case rang
    }

    /// Each followed timer by its id. One whose start wasn't read (it began
    /// before the replayed window) isn't followed: its end is unknown.
    public private(set) var timers: [String: Phase] = [:]

    public init() {}

    /// The one the bar shows: a ringing timer, else the one ending first,
    /// else the paused one with the least left.
    public var current: Phase? {
        let phases = timers.values
        if phases.contains(.rang) { return .rang }
        let ends = phases.compactMap { phase -> Date? in
            if case .running(let ends) = phase { ends } else { nil }
        }
        if let first = ends.min() { return .running(ends: first) }
        let lefts = phases.compactMap { phase -> TimeInterval? in
            if case .paused(let left) = phase { left } else { nil }
        }
        return lefts.min().map { .paused(left: $0) }
    }

    /// Folds one mobiletimerd message in. True when a timer changed.
    @discardableResult
    public mutating func read(_ message: String, at date: Date) -> Bool {
        let before = timers
        if let added = message.range(of: Self.added) {
            for timer in Self.timers(in: message[added.upperBound...]) where timer.state == "Running" {
                timers[timer.id] = .running(ends: date.addingTimeInterval(timer.duration))
            }
        } else if message.contains(Self.updated), let now = message.range(of: Self.toTimers) {
            for timer in Self.timers(in: message[now.upperBound...]) { fold(timer, at: date) }
        }
        return timers != before
    }

    private mutating func fold(_ timer: Logged, at date: Date) {
        let was = timers[timer.id]
        switch timer.state {
        case "Running":
            switch was {
            case .paused(let left)?: timers[timer.id] = .running(ends: date.addingTimeInterval(left))
            case .rang?: timers[timer.id] = .running(ends: date.addingTimeInterval(timer.duration))
            case .running?, nil: break  // running already, or never followed
            }
        case "Paused":
            if case .running(let ends)? = was { timers[timer.id] = .paused(left: max(0, ends.timeIntervalSince(date))) }
        case "Stopped":
            // The Clock keeps its presets as stopped timers: never followed.
            guard was != nil else { return }
            timers[timer.id] = timer.fired && !timer.dismissed ? .rang : nil
        default:
            break
        }
    }

    static let added = "didAddTimers ("
    static let updated = "didUpdateTimers fromTimers:"
    static let toTimers = ") toTimers: ("

    /// The lines worth reading, for a `log` predicate.
    public static let predicate =
        #"process == "mobiletimerd" AND subsystem == "com.apple.mobiletimer.logging" AND category == "Timers" AND (eventMessage CONTAINS "didAddTimers" OR eventMessage CONTAINS "didUpdateTimers")"#

    struct Logged: Equatable {
        let id: String
        let state: String
        let duration: TimeInterval
        let fired: Bool
        let dismissed: Bool
    }

    /// Every timer description in `text`, in order.
    static func timers(in text: Substring) -> [Logged] {
        var found: [Logged] = []
        var rest = text
        while let start = rest.range(of: "TimerID: ") {
            rest = rest[start.upperBound...]
            let end = rest.range(of: "TimerID: ")?.lowerBound ?? rest.endIndex
            let one = rest[..<end]
            let id = String(one.prefix(36))
            guard id.count == 36,
                  let state = field(", state:", in: one, upTo: ","),
                  let duration = field(", duration:", in: one, upTo: ",").flatMap({ TimeInterval($0) }),
                  let fired = field(", firedDate: ", in: one, upTo: ", dismissedDate:"),
                  let dismissed = field(", dismissedDate: ", in: one, upTo: ",")
            else { continue }
            found.append(Logged(id: id, state: String(state), duration: duration,
                                fired: fired != "(null)", dismissed: dismissed != "(null)"))
        }
        return found
    }

    /// The text between `name` and the next `stop`.
    static func field(_ name: String, in text: Substring, upTo stop: String) -> Substring? {
        guard let start = text.range(of: name) else { return nil }
        let value = text[start.upperBound...]
        guard let end = value.range(of: stop) else { return nil }
        return value[..<end.lowerBound]
    }
}
