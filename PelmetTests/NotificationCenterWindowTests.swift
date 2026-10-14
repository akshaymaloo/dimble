import CoreGraphics
import Testing
@testable import Pelmet

/// Notification Center's windows are told apart by their owner's pid. The
/// owner NAME is localized — "알림 센터" on a Korean Mac — so matching
/// "Notification Center" read the panel as closed everywhere but English:
/// the shortcut pressed again and closed a panel that had fully opened, and
/// the panel's windows counted as backdrop.
struct NotificationCenterWindowTests {
    let pid: pid_t = 512

    func window(owner: String, pid: pid_t) -> [String: Any] {
        [kCGWindowOwnerName as String: owner, kCGWindowOwnerPID as String: pid]
    }

    @Test func theEnglishNameIsFoundByPid() {
        #expect(ClockClickRelay.isNotificationCenterWindow(window(owner: "Notification Center", pid: pid), pid: pid))
    }

    @Test func aLocalizedNameIsFoundByPid() {
        #expect(ClockClickRelay.isNotificationCenterWindow(window(owner: "알림 센터", pid: pid), pid: pid))
        #expect(ClockClickRelay.isNotificationCenterWindow(window(owner: "Centre de notifications", pid: pid), pid: pid))
    }

    @Test func anotherProcessWithTheNameIsNot() {
        #expect(!ClockClickRelay.isNotificationCenterWindow(window(owner: "Notification Center", pid: 99), pid: pid))
    }

    @Test func withoutAPidTheEnglishNameStandsIn() {
        // The process not found: what was matched before, no worse.
        #expect(ClockClickRelay.isNotificationCenterWindow(window(owner: "Notification Center", pid: 99), pid: nil))
        #expect(!ClockClickRelay.isNotificationCenterWindow(window(owner: "알림 센터", pid: 99), pid: nil))
    }

    @Test func anEntryWithoutAnOwnerPidIsNot() {
        #expect(!ClockClickRelay.isNotificationCenterWindow([kCGWindowOwnerName as String: "알림 센터"], pid: pid))
    }

    /// A tall window of Notification Center's own process, as the panel is.
    func panel(number: Int = 7, layer: Int = 21, height: CGFloat = 900, alpha: Double = 1) -> [String: Any] {
        [kCGWindowOwnerPID as String: pid, kCGWindowNumber as String: number, kCGWindowLayer as String: layer,
         kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 400, "Height": height] as [String: CGFloat],
         kCGWindowAlpha as String: alpha]
    }

    @Test func aTallVisibleWindowOnARealLayerReadsAsThePanel() {
        #expect(ClockClickRelay.panelWindows(in: [panel()], pid: pid, ignoring: []).count == 1)
    }

    @Test func aDesktopLayerShortOrInvisibleWindowDoesNot() {
        #expect(ClockClickRelay.panelWindows(in: [panel(layer: -2147483603)], pid: pid, ignoring: []).isEmpty)
        #expect(ClockClickRelay.panelWindows(in: [panel(height: 200)], pid: pid, ignoring: []).isEmpty)
        #expect(ClockClickRelay.panelWindows(in: [panel(alpha: 0)], pid: pid, ignoring: []).isEmpty)
    }

    @Test func aWindowWithoutAnAlphaCountsAsVisible() {
        var window = panel()
        window[kCGWindowAlpha as String] = nil
        #expect(ClockClickRelay.panelWindows(in: [window], pid: pid, ignoring: []).count == 1)
    }

    @Test func aPhantomWindowIsSkippedAndAnotherIsNot() {
        let windows = [panel(number: 7), panel(number: 8)]
        let open = ClockClickRelay.panelWindows(in: windows, pid: pid, ignoring: [7])
        #expect(open.compactMap(ClockClickRelay.windowNumber) == [8])
    }
}
