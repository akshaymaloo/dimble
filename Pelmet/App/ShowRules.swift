// ShowRules.swift
// #86: keep a hidden icon on the bar while its state matters. Each rule sits
// behind its own launch argument until the "Show when…" choice lands:
//   pelmet.debug.showOnBattery         Battery while on battery power
//   pelmet.debug.showWifiDisconnected  Wi-Fi while it's on and joined to no
//                                      network (off is on purpose, so it stays)
//   pelmet.debug.showDuringBackup      Pelmet's Time Machine item while a
//                                      backup runs (the extras manager reads it)
// The engine shows Battery and Wi-Fi the way a press does: their section
// stays hidden, nothing else reflows. macOS doesn't draw a hidden icon, so
// each state is read from the system, never from the icon.

import Foundation
import IOKit.ps
import notify
import PelmetCore
import PelmetEngine
import SystemConfiguration

@MainActor
final class ShowRules {
    enum Rule: String, CaseIterable {
        case onBattery = "pelmet.debug.showOnBattery"
        case wifiDisconnected = "pelmet.debug.showWifiDisconnected"
        case backingUp = "pelmet.debug.showDuringBackup"

        var isOn: Bool { UserDefaults.standard.bool(forKey: rawValue) }
    }

    static let battery = ItemID(rawValue: "status:com.apple.MenuBarAgent::com.apple.menuextra.battery")
    static let wifi = ItemID(rawValue: "status:com.apple.MenuBarAgent::com.apple.menuextra.wifi")

    /// Wi-Fi drops its network for a few seconds on every wake and every
    /// roam: only a disconnection that lasts this long shows the icon.
    static let wifiGrace: Duration = .seconds(5)

    private let apply: (Set<ItemID>) -> Void
    private var powerToken: Int32 = NOTIFY_TOKEN_INVALID
    private var store: SCDynamicStore?
    private var storeSource: CFRunLoopSource?
    private var wifiInterface: String?
    private var wifiDown = false
    private var wifiGraceTask: Task<Void, Never>?
    private var shown: Set<ItemID>?
    private var lastLine: [Rule: String] = [:]

    init?(apply: @escaping (Set<ItemID>) -> Void) {
        let battery = Rule.onBattery.isOn, wifi = Rule.wifiDisconnected.isOn
        guard battery || wifi else { return nil }
        self.apply = apply
        if battery {
            notify_register_dispatch(kIOPSNotifyPowerSource, &powerToken, .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            }
        }
        if wifi { watchWifi() }
        evaluate()
    }

    // Isolated: the store's source holds an unretained pointer to self, so it
    // must leave the run loop before self goes.
    isolated deinit {
        if powerToken != NOTIFY_TOKEN_INVALID { notify_cancel(powerToken) }
        if let storeSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), storeSource, .commonModes) }
    }

    // MARK: Wi-Fi

    private func watchWifi() {
        let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []
        wifiInterface = interfaces.first {
            SCNetworkInterfaceGetInterfaceType($0) == kSCNetworkInterfaceTypeIEEE80211
        }.flatMap { SCNetworkInterfaceGetBSDName($0) as String? }
        guard let name = wifiInterface else {
            PelmetLog.log("rule: no Wi-Fi interface, the Wi-Fi rule has nothing to watch")
            return
        }
        var context = SCDynamicStoreContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        guard let store = SCDynamicStoreCreate(nil, "Pelmet.ShowRules" as CFString, { _, _, info in
            guard let info else { return }
            let rules = Unmanaged<ShowRules>.fromOpaque(info).takeUnretainedValue()
            MainActor.assumeIsolated { rules.evaluate() }
        }, &context) else { return }
        let keys = [Self.linkKey(name), Self.airportKey(name)] as CFArray
        SCDynamicStoreSetNotificationKeys(store, keys, nil)
        let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.store = store
        storeSource = source
    }

    private static func linkKey(_ name: String) -> String { "State:/Network/Interface/\(name)/Link" }
    private static func airportKey(_ name: String) -> String { "State:/Network/Interface/\(name)/AirPort" }

    /// On, and joined to no network. Nil when the store can't say.
    private func wifiDisconnected() -> Bool? {
        guard let store, let name = wifiInterface else { return nil }
        let airport = SCDynamicStoreCopyValue(store, Self.airportKey(name) as CFString) as? [String: Any]
        let link = SCDynamicStoreCopyValue(store, Self.linkKey(name) as CFString) as? [String: Any]
        let powered = (airport?["Power Status"] as? NSNumber)?.boolValue ?? false
        let joined = (link?["Active"] as? NSNumber)?.boolValue ?? false
        return powered && !joined
    }

    // MARK: Evaluate

    private func evaluate() {
        var items: Set<ItemID> = []
        if Rule.onBattery.isOn {
            let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
            let source = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
            let onBattery = source == kIOPSBatteryPowerValue
            note(.onBattery, onBattery ? "on battery, Battery shows" : "on power, Battery follows its section")
            if onBattery { items.insert(Self.battery) }
        }
        if Rule.wifiDisconnected.isOn, let down = wifiDisconnected() {
            if down, !wifiDown {
                // Shown only if the grace runs out still disconnected.
                wifiDown = true
                note(.wifiDisconnected, "Wi-Fi joined to no network, shows in \(Self.wifiGrace) unless it rejoins")
                wifiGraceTask?.cancel()
                wifiGraceTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.wifiGrace)
                    guard !Task.isCancelled, let self else { return }
                    self.wifiGraceTask = nil
                    self.evaluate()
                }
            } else if !down {
                wifiDown = false
                wifiGraceTask?.cancel()
                wifiGraceTask = nil
                note(.wifiDisconnected, "Wi-Fi joined or off, Wi-Fi follows its section")
            }
            if down, wifiGraceTask == nil {
                note(.wifiDisconnected, "Wi-Fi still joined to no network, Wi-Fi shows")
                items.insert(Self.wifi)
            }
        }
        guard items != shown else { return }
        shown = items
        apply(items)
    }

    /// One line per change of a rule's state, not per notification.
    private func note(_ rule: Rule, _ line: String) {
        guard lastLine[rule] != line else { return }
        lastLine[rule] = line
        PelmetLog.log("rule: \(line)")
    }
}
