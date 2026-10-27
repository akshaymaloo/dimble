// LiveActivityStatus.swift
// Which Live Activities are running, for Dimble's Live Activities item
// (#106). MenuBarAgent takes their pills off the bar under any hide
// assertion, and what an activity shows is for Apple's own processes only
// (the session and chrono services check private entitlements). The agent
// does narrate each one's start and end to the unified log, naming the app
// (`LiveActivities`), so one `log stream` child follows those lines the way
// FocusStatus follows donotdisturbd, and `log show` replays the last eight
// hours at boot: no activity runs longer.

import AppKit
import PelmetCore
import PelmetEngine

@MainActor
final class LiveActivityStatus {
    private(set) var activities = LiveActivities() {
        didSet {
            guard activities.active != oldValue.active else { return }
            onChange?()
            scheduleExpiry()
        }
    }
    /// Oldest first.
    var active: [LiveActivity] { activities.active }
    /// Fires on the main actor whenever `active` changes.
    var onChange: (() -> Void)?

    private var stream: Process?
    private var stopped = false
    /// Live lines that land while the replay is still reading the log: they
    /// are newer than it, so they fold in on top of it.
    private var recovering = false
    private var pending: [Entry] = []
    private var restarts = 0
    /// Pelmet quitting takes the child with it (see FocusStatus).
    private var termination: NSObjectProtocol?
    /// Wakes for the oldest activity's lifetime, or sooner to check the
    /// agent that announced them is still the one running.
    private var expiry: Task<Void, Never>?

    /// One ndjson line: the message, when it was logged, and by which
    /// MenuBarAgent.
    struct Entry: Sendable {
        let message: String
        let date: Date
        let agent: Int32
    }

    func start() {
        stopped = false
        reapOrphans()
        if termination == nil {
            termination = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.stop() } }
        }
        recover()
        openStream()
    }

    func stop() {
        stopped = true
        pending = []
        expiry?.cancel()
        (stream?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        stream?.terminate()
        stream = nil
    }

    /// Any `log stream` on our predicate re-parented to launchd is ours.
    private func reapOrphans() {
        Task.detached(priority: .utility) {
            let pids = FocusStatus.run(["/usr/bin/pgrep", "-P", "1", "-f", "Create client element for Live Activity"])
                .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            for pid in pids { kill(pid, SIGTERM) }
            if !pids.isEmpty { PelmetLog.log("liveactivity: reaped \(pids.count) orphaned log stream(s)") }
        }
    }

    // MARK: Boot

    /// Replays the last eight hours, then lets go of what the running agent
    /// can't still be showing: one past its lifetime, one a MenuBarAgent
    /// that has since gone announced (the Mac restarted, the agent died
    /// before its end lines). This Mac's log kept these lines ~21 hours
    /// (2026-10-27), so eight is always on record; reading them took 2.1s.
    private func recover() {
        recovering = true
        Task.detached(priority: .utility) { [weak self] in
            let entries = FocusStatus.run(["show", "--last", "8h", "--style", "ndjson", "--predicate", LiveActivities.predicate])
                .compactMap(Self.entry(in:))
            var replayed = LiveActivities()
            for entry in entries { replayed.read(entry.message, at: entry.date, agent: entry.agent) }
            let dropped = replayed.prune(now: Date(), agent: Self.agentPID())
            await MainActor.run { [weak self] in
                guard let self, !self.stopped else { return }
                for entry in self.pending { replayed.read(entry.message, at: entry.date, agent: entry.agent) }
                self.pending = []
                self.recovering = false
                PelmetLog.log("liveactivity: boot \(Self.describe(replayed))\(dropped ? " (ended ones the log never closed dropped)" : "")\(entries.isEmpty ? ", nothing on record" : "")")
                self.activities = replayed
            }
        }
    }

    /// The running MenuBarAgent's pid; nil when it isn't up.
    nonisolated private static func agentPID() -> Int32? {
        NSRunningApplication.runningApplications(withBundleIdentifier: PelmetBundle.agentID).first?.processIdentifier
    }

    // MARK: Live

    private func openStream() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "ndjson", "--predicate", LiveActivities.predicate]
        let pipe = Pipe()
        process.standardOutput = pipe
        let errors = Pipe()
        process.standardError = errors
        let lines = FocusStatus.LineSplitter()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
            for text in lines.split(appending: chunk) {
                guard let entry = Self.entry(in: text) else { continue }
                Task { @MainActor [weak self] in
                    guard let self, !self.stopped else { return }
                    guard !self.recovering else { self.pending.append(entry); return }
                    var next = self.activities
                    guard next.read(entry.message, at: entry.date, agent: entry.agent) else {
                        self.activities = next  // a requester noted for the start line behind it
                        return
                    }
                    PelmetLog.log("liveactivity: \(Self.describe(next))")
                    self.activities = next
                }
            }
        }
        process.terminationHandler = { [weak self] _ in
            // Why `log` quit, when it says (it has a "Must be admin" refusal).
            let why = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .split(separator: "\n").first.map(String.init) ?? ""
            Task { @MainActor [weak self] in self?.streamEnded(why) }
        }
        do {
            try process.run()
            stream = process
        } catch {
            PelmetLog.log("liveactivity: log stream failed — \(error.localizedDescription)")
        }
    }

    /// logd restarts (or a kill) end the child; back off like FocusStatus.
    /// The replay on the way back catches an end the gap swallowed.
    private func streamEnded(_ why: String) {
        stream = nil
        guard !stopped else { return }
        restarts += 1
        let delay = min(60, 2 << min(restarts, 5))
        PelmetLog.log("liveactivity: log stream ended\(why.isEmpty ? "" : " (\(why.prefix(120)))"), retry in \(delay)s")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !self.stopped, self.stream == nil else { return }
            self.recover()
            self.openStream()
        }
    }

    // MARK: Expiry

    /// An end line the log never delivered would keep an activity forever:
    /// it goes at its lifetime, or as soon as the agent that announced it
    /// is gone. Checked every ten minutes while any runs.
    private func scheduleExpiry() {
        expiry?.cancel()
        guard let due = activities.nextExpiry else { return }
        let wake = min(due, Date().addingTimeInterval(600))
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, wake.timeIntervalSinceNow)))
            // A replay landing after this one only overwrites what it pruned.
            guard let self, !Task.isCancelled, !self.stopped else { return }
            var next = self.activities
            if next.prune(now: Date(), agent: Self.agentPID()) {
                PelmetLog.log("liveactivity: no end line came — \(Self.describe(next))")
                self.activities = next
            } else {
                self.scheduleExpiry()
            }
        }
    }

    // MARK: Plumbing

    nonisolated private static func describe(_ activities: LiveActivities) -> String {
        guard !activities.active.isEmpty else { return "none running" }
        return "\(activities.active.count) running — " + activities.active
            .map { "\($0.id) \($0.bundleID ?? "app unnamed")" }
            .joined(separator: ", ")
    }

    /// The message, time and agent pid of one ndjson line; nil for the
    /// header line the stream prints first, the trailing count `log show`
    /// appends, and another logged-in user's agent (one runs per user).
    nonisolated private static func entry(in line: String) -> Entry? {
        guard line.hasPrefix("{"),
              let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              (object["userID"] as? Int).map({ $0 == Int(getuid()) }) ?? true,
              let message = object["eventMessage"] as? String,
              let pid = object["processID"] as? Int
        else { return nil }
        // `log`'s ndjson timestamps: "2026-10-27 08:16:19.694652-0400".
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        let date = (object["timestamp"] as? String).flatMap(formatter.date(from:)) ?? Date()
        return Entry(message: message, date: date, agent: Int32(pid))
    }
}
