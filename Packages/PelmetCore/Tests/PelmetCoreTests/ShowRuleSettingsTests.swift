import Foundation
import Testing
@testable import PelmetCore

struct ShowRuleSettingsTests {
    // On battery power alone, or only once the charge is under 20%.
    @Test func batteryConditionsReadPowerAndCharge() {
        #expect(BatteryShowCondition.onBattery.isMet(onBattery: true, percent: 90))
        #expect(BatteryShowCondition.onBattery.isMet(onBattery: true, percent: nil))
        #expect(!BatteryShowCondition.onBattery.isMet(onBattery: false, percent: 5))

        #expect(BatteryShowCondition.below20.isMet(onBattery: true, percent: 19))
        #expect(!BatteryShowCondition.below20.isMet(onBattery: true, percent: 20))
        #expect(!BatteryShowCondition.below20.isMet(onBattery: true, percent: 80))
        // Plugged in, a low charge is already being fixed.
        #expect(!BatteryShowCondition.below20.isMet(onBattery: false, percent: 4))
        // A charge that can't be read says nothing.
        #expect(!BatteryShowCondition.below20.isMet(onBattery: true, percent: nil))
    }

    // A blob from before the rules existed decodes with every rule off.
    @Test func settingsDefaultOffAndRoundTrip() throws {
        let legacy = try JSONDecoder().decode(SettingsStore.self, from: Data("{}".utf8))
        #expect(legacy.showRules == ShowRuleSettings())
        #expect(legacy.showRules.battery == nil && !legacy.showRules.wifiOn)

        var settings = SettingsStore()
        settings.showRules.batteryOn = true
        settings.showRules.batteryCondition = .below20
        settings.showRules.wifiOn = true
        let back = try JSONDecoder().decode(SettingsStore.self, from: JSONEncoder().encode(settings))
        #expect(back.showRules == settings.showRules)
        #expect(back.showRules.battery == .below20)
    }

    // One unreadable field resets that field alone, not the whole store.
    @Test func badFieldsFallBackOneByOne() throws {
        let blob = #"{"showRules":{"batteryOn":true,"batteryCondition":"nonsense","wifiOn":true},"autoRehide":false}"#
        let store = try JSONDecoder().decode(SettingsStore.self, from: Data(blob.utf8))
        #expect(store.showRules.batteryOn)
        #expect(store.showRules.batteryCondition == .onBattery)
        #expect(store.showRules.wifiOn)
        #expect(!store.autoRehide)
        let partial = try JSONDecoder().decode(ShowRuleSettings.self, from: Data(#"{"wifiOn":true}"#.utf8))
        #expect(partial.wifiOn && !partial.batteryOn)
    }

    // Switching the rule off keeps the condition for the next time.
    @Test func conditionSurvivesSwitchingOff() {
        var rules = ShowRuleSettings()
        rules.batteryCondition = .below20
        rules.batteryOn = true
        #expect(rules.battery == .below20)
        rules.batteryOn = false
        #expect(rules.battery == nil)
        #expect(rules.batteryCondition == .below20)
    }

    // An icon that isn't in the menu bar, or sits in Visible, has nothing to
    // come back from.
    @Test func availabilityFollowsPresenceAndSection() {
        #expect(ShowRuleAvailability(inMenuBar: true, section: .hidden) == .applies)
        #expect(ShowRuleAvailability(inMenuBar: true, section: .alwaysHidden) == .applies)
        #expect(ShowRuleAvailability(inMenuBar: true, section: .visible) == .inVisible)
        #expect(ShowRuleAvailability(inMenuBar: false, section: .hidden) == .notInMenuBar)
        // Not being in the bar outranks where the model filed it.
        #expect(ShowRuleAvailability(inMenuBar: false, section: .visible) == .notInMenuBar)
    }

    // The card lists these two; launchers keep their own rule on their row,
    // Media its indicator picker (an indicator again, 2026-10-12).
    @Test func onlyActivityDrivenItemsShowWhenItMatters() {
        let listed = ExtraKind.allCases.filter(\.showsWhenItMatters)
        #expect(Set(listed) == [.focus, .timeMachine])
        // Media comes out while playing, Focus and Time Machine stay put.
        #expect(ExtraKind.mediaControls.defaultShowRule == .whenActive)
        #expect(ExtraKind.focus.defaultShowRule == .always)
        #expect(ExtraKind.timeMachine.defaultShowRule == .always)
    }
}
