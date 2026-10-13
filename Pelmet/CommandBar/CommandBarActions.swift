// CommandBarActions.swift
// What ⌘K offers on a row (docs/COMMAND-BAR.md): the item's own presses with
// the keys that run them, moving it between sections, a shortcut and an alias
// for it, its app, and dropping it from the search history. Built when ⌘K is
// pressed from the row's entry and the settings as they are then.

import AppKit
import PelmetCore

enum CommandBarAction: Equatable {
    case openMenu, showInBar
    case move(PelmetCore.Section)
    case setShortcut, removeShortcut
    case setAlias
    case openApp, quitApp
    case forget
    /// A launcher's only press: start the app.
    case openLauncher

    /// Stable key for the row and the log.
    var key: String {
        switch self {
        case .openMenu: "openMenu"
        case .showInBar: "showInBar"
        case .move(let section): "move.\(section.rawValue)"
        case .setShortcut: "setShortcut"
        case .removeShortcut: "removeShortcut"
        case .setAlias: "setAlias"
        case .openApp: "openApp"
        case .quitApp: "quitApp"
        case .forget: "forget"
        case .openLauncher: "openLauncher"
        }
    }
}

struct CommandBarActionItem {
    let action: CommandBarAction
    let title: String
    let symbol: String
    /// The key that runs it from the results too ("↩", "⌘↩"), or what it
    /// holds now (a shortcut, an alias).
    let trailing: String?
}

@MainActor
enum CommandBarActions {
    /// Empty for rows ⌘K does nothing on (commands, settings).
    static func list(for entry: CommandBarEntry, appState: AppState, history: SearchHistory) -> [CommandBarActionItem] {
        func pick(_ first: String, _ second: String) -> String { CommandBarCorpus.pick(first, second) }
        func item(_ action: CommandBarAction, _ title: String, _ symbol: String, _ trailing: String? = nil) -> CommandBarActionItem {
            CommandBarActionItem(action: action, title: title, symbol: symbol, trailing: trailing)
        }
        let canForget = history.hasPicks(for: entry.candidate.id)

        switch entry.action {
        case .launcher:
            var out = [item(.openLauncher, String(localized: "Open \(entry.candidate.title)"), "arrow.up.forward.app")]
            if canForget { out.append(item(.forget, String(localized: "Forget"), pick("eraser", "xmark.circle"))) }
            return out

        case .item(let id):
            // Titles, move targets and Quit come from ItemMenuActions, so ⌘K
            // and a tile's right-click menu say the same thing.
            var out = [
                item(.openMenu, ItemMenuActions.openMenuTitle, "cursorarrow.click", "↩"),
                item(.showInBar, ItemMenuActions.showInBarTitle, "eye", "⌘↩"),
            ]
            for section in ItemMenuActions.moveTargets(of: id, appState: appState) {
                let symbol = switch section {
                case .visible: "menubar.rectangle"
                case .hidden: "eye.slash"
                case .alwaysHidden: pick("eye.slash.circle", "eye.slash")
                }
                out.append(item(.move(section), ItemMenuActions.moveTitle(section), symbol))
            }
            let shortcut = appState.settings.itemHotkeys[id.rawValue]
            out.append(item(
                .setShortcut, ItemMenuActions.shortcutTitle(id, appState: appState), "keyboard", shortcut?.display
            ))
            if shortcut != nil {
                out.append(item(.removeShortcut, String(localized: "Remove Shortcut"), "xmark.circle"))
            }
            let alias = appState.settings.itemAliases[id.rawValue]
            out.append(item(
                .setAlias,
                alias == nil ? String(localized: "Add Alias…") : String(localized: "Edit Alias…"),
                "tag", alias.map { "“\($0)”" }
            ))
            if let app = entry.app {
                out.append(item(.openApp, String(localized: "Open \(app.openName)"), "arrow.up.forward.app"))
                if ItemMenuActions.isRunning(app.bundleID) {
                    out.append(item(.quitApp, ItemMenuActions.quitTitle(app.name), "power"))
                }
            }
            if canForget { out.append(item(.forget, String(localized: "Forget"), pick("eraser", "xmark.circle"))) }
            return out

        case .command, .setting:
            return []
        }
    }

    /// The actions whose titles the query matches, best first (the list's own
    /// order breaks ties); all of them, in order, for an empty query.
    static func filtered(
        _ items: [CommandBarActionItem], query: String
    ) -> [(item: CommandBarActionItem, ranges: [Range<Int>])] {
        guard !FoldedText.normalized(query).isEmpty else { return items.map { ($0, []) } }
        let folded = FoldedText(query)
        let hits: [(offset: Int, item: CommandBarActionItem, match: FuzzyMatch)] = items.enumerated().compactMap { offset, item in
            FuzzyMatcher.match(folded, in: FoldedText(item.title)).map { (offset, item, $0) }
        }
        return hits
            .sorted { $0.match.score != $1.match.score ? $0.match.score > $1.match.score : $0.offset < $1.offset }
            .map { ($0.item, $0.match.ranges) }
    }
}
