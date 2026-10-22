// RecordingPill.swift
// The system's Stop Recording pill (screencaptureui, #42) comes and goes
// with no app launching or quitting: ⇧⌘5 starts the process, Record puts
// the pill up 25ms after `screencapture` logs "Recording started", the stop
// takes it down. Under the assertion that went wrong twice (2026-10-22,
// four recordings): the agent parks an icon that registers while any
// assertion is held, so the pill stayed out of the bar until a reveal
// swapped the assertion, and nothing walked the bar when it came or went,
// so a held picture covered it and its hole outlived it. While the process
// runs, one `log stream` child follows the recording lines and the pill's
// icons are counted twice a second.

import AppKit
import PelmetCore
import PelmetEngine

@MainActor
final class RecordingPill {
    /// `screencapture` started recording: the pill registers next, parked.
    var onRecordingStarted: (() -> Void)?
    /// The pill's icon count in the AX tree changed: the bar wants a walk.
    var onIconsChanged: ((Int) -> Void)?
    /// The process quit, seconds after the stop (the thumbnail): the walk
    /// at the stop could still list the pill mid-teardown (09:57:16, its
    /// hole stayed open), so the bar wants one more.
    var onEnded: (() -> Void)?

    private var watch: Task<Void, Never>?
    private var stream: Process?
    private var termination: NSObjectProtocol?

    nonisolated private static let predicate =
        #"subsystem == "com.apple.screencapture" AND category == "recording" AND eventMessage BEGINSWITH "Recording started""#

    /// Follows one screencaptureui process until it quits.
    func follow(_ capture: NSRunningApplication) {
        stop()
        if termination == nil {
            termination = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.stop() } }
        }
        reapOrphans()
        openStream()
        watch = Task { [weak self] in
            let pid = capture.processIdentifier
            var shown = 0
            while !Task.isCancelled, !capture.isTerminated {
                let count = await Task.detached { Self.iconCount(pid: pid) }.value
                if count != shown {
                    shown = count
                    self?.onIconsChanged?(count)
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            guard !Task.isCancelled else { return }
            self?.onEnded?()
            self?.closeStream()
        }
    }

    func stop() {
        watch?.cancel()
        watch = nil
        closeStream()
    }

    private func openStream() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = ["stream", "--style", "ndjson", "--predicate", Self.predicate]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let lines = FocusStatus.LineSplitter()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
            // The header line has no message; every other line is a start.
            for line in lines.split(appending: chunk) where line.hasPrefix("{") && line.contains("Recording started") {
                Task { @MainActor [weak self] in self?.onRecordingStarted?() }
            }
        }
        do {
            try process.run()
            stream = process
        } catch {
            PelmetLog.log("recording: log stream failed — \(error.localizedDescription)")
        }
    }

    private func closeStream() {
        (stream?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        stream?.terminate()
        stream = nil
    }

    /// A stream left by a Pelmet that crashed mid-recording, re-parented to
    /// launchd (see SharePlayStatus).
    private func reapOrphans() {
        Task.detached(priority: .utility) {
            let pids = FocusStatus.run(["/usr/bin/pgrep", "-P", "1", "-f", #"category == "recording""#])
                .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            for pid in pids { kill(pid, SIGTERM) }
            if !pids.isEmpty { PelmetLog.log("recording: reaped \(pids.count) orphaned log stream(s)") }
        }
    }

    nonisolated static func iconCount(pid: pid_t) -> Int {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return 0 }
        var count: CFIndex = 0
        AXUIElementGetAttributeValueCount(bar as! AXUIElement, kAXChildrenAttribute as CFString, &count)
        return count
    }
}
