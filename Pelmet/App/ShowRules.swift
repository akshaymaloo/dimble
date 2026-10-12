// ShowRules.swift
// #86 spike: keep a hidden icon on the bar while its state matters. One rule
// so far, Battery while on battery, behind the `pelmet.debug.showOnBattery`
// launch argument. The engine shows the item the way a press does: its
// section stays hidden, nothing else reflows.

import Foundation
import IOKit.ps
import notify
import PelmetCore
import PelmetEngine

@MainActor
final class ShowRules {
    static let battery = ItemID(rawValue: "status:com.apple.MenuBarAgent::com.apple.menuextra.battery")

    private var token: Int32 = NOTIFY_TOKEN_INVALID
    private let apply: (Set<ItemID>) -> Void

    init?(apply: @escaping (Set<ItemID>) -> Void) {
        guard UserDefaults.standard.bool(forKey: "pelmet.debug.showOnBattery") else { return nil }
        self.apply = apply
        notify_register_dispatch(kIOPSNotifyPowerSource, &token, .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        evaluate()
    }

    deinit {
        if token != NOTIFY_TOKEN_INVALID { notify_cancel(token) }
    }

    private func evaluate() {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let source = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
        let onBattery = source == kIOPSBatteryPowerValue
        PelmetLog.log("rule: \(onBattery ? "on battery, Battery shows" : "plugged in, Battery follows its section")")
        apply(onBattery ? [Self.battery] : [])
    }
}
