// ShowWhen.swift
// "Show when it matters" (#86) on Settings › Menu Bar: hidden icons that come
// back on the bar while their state matters. The card lists every icon that
// can, and a tile in the editor offers the same choice from its popover. Both
// read and write through `ShowWhenRule`, so they can't disagree.

import AppKit
import PelmetCore
import SwiftUI

/// What an icon waits for before it comes back.
enum ShowWhenCondition: Hashable {
    case onBattery, below20
    case wifiDrops
    case mediaPlaying
    case focusOn
    case backingUp

    var label: LocalizedStringKey {
        switch self {
        case .onBattery: "On battery power"
        case .below20: "Below \(BatteryShowCondition.lowCharge)%"
        case .wifiDrops: "When it drops"
        case .mediaPlaying: "While playing"
        case .focusOn: "While a Focus is on"
        case .backingUp: "While backing up"
        }
    }
}

/// The icons a rule can bring back: Apple's Battery and Wi-Fi, and three of
/// Pelmet's own items.
enum ShowWhenSubject: CaseIterable, Hashable {
    case battery, wifi, media, focus, timeMachine

    /// The subject an editor tile stands for, if it has a rule.
    init?(_ id: ItemID) {
        let key = id.sectionKey
        if key == ShowRules.battery {
            self = .battery
        } else if key == ShowRules.wifi {
            self = .wifi
        } else {
            switch id.pelmetItem {
            case .mediaControls: self = .media
            case .focus: self = .focus
            case .timeMachine: self = .timeMachine
            default: return nil
            }
        }
    }

    /// Apple's own icons, which can be missing from the bar or sit in Visible.
    var appleItem: ItemID? {
        switch self {
        case .battery: ShowRules.battery
        case .wifi: ShowRules.wifi
        case .media, .focus, .timeMachine: nil
        }
    }

    /// Pelmet's own item behind a row, which only has one while it is on.
    var kind: ExtraKind? {
        switch self {
        case .battery, .wifi: nil
        case .media: .mediaControls
        case .focus: .focus
        case .timeMachine: .timeMachine
        }
    }

    var symbol: String {
        switch self {
        case .battery: "battery.100percent"
        case .wifi: "wifi"
        case .media: "playpause.fill"
        case .focus: "moon.fill"
        case .timeMachine: ExtraGlyph.timeMachineSymbol
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .battery: "Battery"
        case .wifi: "Wi-Fi"
        case .media: "Media controls"
        case .focus: "Focus"
        case .timeMachine: "Time Machine"
        }
    }

    /// The name inside a sentence.
    var name: String {
        switch self {
        case .battery: String(localized: "Battery")
        case .wifi: "Wi-Fi"
        case .media: String(localized: "Media controls")
        case .focus: String(localized: "Focus")
        case .timeMachine: String(localized: "Time Machine")
        }
    }

    var conditions: [ShowWhenCondition] {
        switch self {
        case .battery: [.onBattery, .below20]
        case .wifi: [.wifiDrops]
        case .media: [.mediaPlaying]
        case .focus: [.focusOn]
        case .timeMachine: [.backingUp]
        }
    }
}

/// One icon's rule, read and written in the settings.
@MainActor
struct ShowWhenRule {
    let subject: ShowWhenSubject
    let appState: AppState

    private var specIndex: Int? {
        subject.kind.flatMap { kind in appState.settings.extraItems.firstIndex { $0.kind == kind } }
    }

    /// What the person chose, whether or not it can apply right now.
    var isOn: Bool {
        switch subject {
        case .battery: appState.settings.showRules.batteryOn
        case .wifi: appState.settings.showRules.wifiOn
        case .media, .focus, .timeMachine:
            specIndex.map { appState.settings.extraItems[$0].resolvedShowRule == .whenActive } ?? false
        }
    }

    /// The condition in force when it is on, kept while it is off. Only
    /// Battery has a choice of them.
    var condition: ShowWhenCondition {
        switch subject {
        case .battery: appState.settings.showRules.batteryCondition == .below20 ? .below20 : .onBattery
        case .wifi, .media, .focus, .timeMachine: subject.conditions[0]
        }
    }

    /// An Apple icon that isn't in the bar, or sits in Visible, has nothing to
    /// come back from; Pelmet's own items always do.
    var availability: ShowRuleAvailability {
        guard let id = subject.appleItem else { return .applies }
        return ShowRuleAvailability(
            inMenuBar: appState.isInMenuBar(id),
            section: appState.settings.sectionModel.section(of: id)
        )
    }

    /// On and able to apply: what the card shows as on, and the tile marks.
    var isActive: Bool { isOn && availability == .applies }

    func setOn(_ on: Bool) {
        write(on: on, condition: nil)
    }

    /// Picks the condition without touching the switch.
    func setCondition(_ condition: ShowWhenCondition) {
        write(on: nil, condition: condition)
    }

    /// The tile popover's pick: this condition, and on.
    func choose(_ condition: ShowWhenCondition) {
        write(on: true, condition: condition)
    }

    private func write(on: Bool?, condition: ShowWhenCondition?) {
        switch subject {
        case .battery:
            if let on { appState.settings.showRules.batteryOn = on }
            if let condition { appState.settings.showRules.batteryCondition = condition == .below20 ? .below20 : .onBattery }
        case .wifi:
            if let on { appState.settings.showRules.wifiOn = on }
        case .media, .focus, .timeMachine:
            guard let on, let index = specIndex else { return }
            appState.settings.extraItems[index].showRule = on ? .whenActive : .always
        }
        appState.settingsChanged()
    }
}

// MARK: - Card

/// The last card on the tab: every icon that can come back on its own, with
/// the condition and a switch.
struct ShowWhenCard: View {
    @Environment(AppState.self) private var appState

    /// Battery and Wi-Fi always; a Pelmet item only while it is on.
    private var subjects: [ShowWhenSubject] {
        ShowWhenSubject.allCases.filter { subject in
            subject.kind.map { kind in appState.settings.extraItems.contains { $0.kind == kind } } ?? true
        }
    }

    var body: some View {
        // Whether Battery or Wi-Fi is in the bar is read with a grace (an
        // icon in a gap isn't missing); the tick lets the answer settle once
        // it has run out, with nothing else changing.
        TimelineView(.periodic(from: .now, by: 4)) { _ in
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(
                    symbol: "bolt.fill", title: "Show when it matters",
                    caption: "Hidden icons that come back on their own"
                ) { EmptyView() }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(subjects, id: \.self) { subject in
                        ShowWhenRow(rule: ShowWhenRule(subject: subject, appState: appState))
                    }
                }
                .pelmetCardSurface()
            }
        }
    }
}

private struct ShowWhenRow: View {
    let rule: ShowWhenRule

    var body: some View {
        let availability = rule.availability
        let applies = availability == .applies
        ItemRowShell(symbol: rule.subject.symbol, title: rule.subject.title) {
            if !applies {
                ShowWhenUnavailable(subject: rule.subject, availability: availability)
            }
        } trailing: {
            condition
                .opacity(applies ? 1 : 0.5)
                .disabled(!applies)
            Toggle("", isOn: Binding(get: { rule.isActive }, set: rule.setOn))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(!applies)
        }
    }

    /// A choice of conditions is a menu in the accent colour; a single one is
    /// just said.
    @ViewBuilder private var condition: some View {
        if rule.subject.conditions.count > 1 {
            // PelmetMenuPicker's borderless menu is secondary grey and has no
            // accent variant; this is the same menu in the accent.
            Menu {
                ForEach(rule.subject.conditions, id: \.self) { condition in
                    Toggle(condition.label, isOn: Binding(
                        get: { rule.condition == condition },
                        set: { if $0 { rule.setCondition(condition) } }
                    ))
                }
            } label: {
                Text(rule.condition.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .menuStyle(.borderlessButton)
            .font(.caption)
            .foregroundStyle(PelmetAccent.accent)
        } else {
            Text(rule.condition.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Why a rule can't apply and what to do about it. Nothing when it can.
struct ShowWhenUnavailable: View {
    let subject: ShowWhenSubject
    let availability: ShowRuleAvailability

    var body: some View {
        switch availability {
        case .applies:
            EmptyView()
        case .notInMenuBar:
            VStack(alignment: .leading, spacing: 2) {
                Text("\(subject.name) is off in System Settings › Menu Bar.")
                Button("Open Menu Bar Settings") { Self.openMenuBarSettings() }
                    .buttonStyle(.plain)
                    .foregroundStyle(PelmetAccent.accent)
            }
        case .inVisible:
            Text("\(subject.name) is in Visible, so it's always on the bar.")
        }
    }

    /// The Control Center settings extension is the one that hosts the Menu
    /// Bar pane.
    private static func openMenuBarSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
    }
}

// MARK: - Tile popover

/// What an editor tile offers when it is clicked: when the icon shows up on
/// the bar. The same choice as the card, as a checkmark list.
struct TileRulePopover: View {
    let id: ItemID
    let name: String
    let rule: ShowWhenRule

    var body: some View {
        let availability = rule.availability
        let applies = availability == .applies
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TileGlyph(id: id)
                Text(name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Shows up on the bar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                choice(Text("Never"), selected: !rule.isActive) { rule.setOn(false) }
                ForEach(rule.subject.conditions, id: \.self) { condition in
                    choice(Text(condition.label), selected: rule.isActive && rule.condition == condition) {
                        rule.choose(condition)
                    }
                }
            }
            .disabled(!applies)
            if !applies {
                ShowWhenUnavailable(subject: rule.subject, availability: availability)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if rule.subject == .wifi {
                Text("Waits 5 seconds, so a wake or a roam doesn't flash it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        // One signal per state: the checkmark marks the choice, no focus ring
        // competing with it (as in the separator options).
        .focusEffectDisabled()
    }

    private func choice(_ label: Text, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PelmetAccent.accent)
                    .opacity(selected ? 1 : 0)
                label
                Spacer(minLength: 0)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
