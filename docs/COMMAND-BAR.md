# Command bar: search the menu bar from the keyboard

Status: decided 2026-10-04, building on `roster`. Answers discussion #73 ("shortcut → type → Enter opens that item's menu → arrow keys from there").

Decisions (Gab, 2026-10-04): panel under the bar at the right, like the tray. Default shortcut ⌥⌘K (⌥⌘Space belongs to Finder's search window). v1 ships with the ⌘K actions. The tray's press relay is lifted onto `roster` on its own, the tray stays on its branch.

Naming rule: every type, file, log prefix and UI string is Pelmet's own (same rule as `CORE-SETS.md`).

## Why

Hidden icons are out of sight by design, so reaching one costs a reveal, a hunt and a click. Keyboard-first people want the shortest path: a shortcut, two or three letters, Return, and they are inside the menu. Today every menu bar search on macOS is a flat list matched on names only, and the common complaints are the same everywhere: the first keystroke is lost, Return takes seconds to show anything, items have no names, visible icons crowd the list, always-hidden items do nothing.

## Principles

1. **Return lands in the menu.** The menu opens under the item's own icon in the real bar, with keyboard focus, so arrow keys and type-to-select work as they do natively. Nothing is a proxy.
2. **Fast or it's broken.** Hotkey → typing in under 50ms, a keystroke → results in one frame, Return → menu in under 400ms for a hidden item.
3. **The system does the hard work.** Pelmet knows names, synonyms, what you picked last time and what is hidden. You type less than you would anywhere else.
4. **Local only.** History and learned queries stay on the Mac, in their own defaults key, with a reset. No analytics, same as the rest of the app.
5. **One press recipe.** The command bar and the floating tray press items through the same relay. Two surfaces, one way to open a menu.

## The experience (v1)

**Open.** A global shortcut, ⌥⌘K by default (new `HotkeyManager` slot, recorder in Settings › General), "Search…" in the right-click menu, and a Shortcuts action later. The panel is a non-activating glass panel under the bar at the right, anchored like the tray, so the app you were in stays frontmost and gets focus back on close. The field is key in the same runloop turn as the hotkey, so the first letter is never lost.

**Rest state.** The field plus up to five rows: the hidden icons you open most, most recent first. No history yet → hidden icons in bar order. No headers, no section groups.

**Row.** The item's real bar glyph at bar scale (the app icon when Screen Recording is off), its name, the app name in secondary ink when it differs ("Wi-Fi · Control Center"), and a quiet trailing tag for Hidden / Always Hidden. When an alias or synonym matched, the row says so ("bt → Bluetooth"). Selection is a soft fill, never a border.

**Typing.** Results update per keystroke. The top hit completes inline after the caret in tertiary ink; Tab or → accepts it, typing through it keeps it. The top row is always selected, so Return just works.

**Return.** The panel fades out (exit no longer than its entrance), the item is revealed if hidden, pressed, and its menu takes focus. The item stays revealed until its menu is gone, then the rehide machine conceals as usual.

| Key | Does |
|---|---|
| ↩ | Open the item's menu |
| ⌘↩ | Show it in the bar without clicking (reveals its section) |
| ⌘K | Actions for the selected row ("Actions", below); again or ⎋ goes back |
| ⌘, | Settings |
| ⎋ or the shortcut again | Close, focus returns to the previous app |

**Not running.** An app Pelmet knows (launchers) whose icon is absent shows as "Dropbox isn't running" with ↩ to open it.

**Settings in the same field.** Setting rows are searchable by their label and keywords ("hover" → "Reveal on hover · General"). Return opens Settings on that tab, scrolled to the row, with a one-time highlight (`AppState.settingsFocusRow`, taken and cleared by the Settings view; a soft accent fill that fades over a second, no outline). The index covers General and Behavior; each indexed row carries a `.settingAnchor(id)` in `SettingsView.swift`. Pelmet commands live here too: Show all, Edit layout, Animation ▸ Fade, Check for updates, Quit Pelmet. Items rank above commands unless the command matches clearly better.

## Actions (⌘K)

⌘K on an item row swaps the results for that row's actions in the same panel. The field wears a quiet chip with the item's glyph and name ("Wi-Fi ›", low-alpha fill, no border) and typing filters the actions with `FuzzyMatcher`. ⎋ or ⌘K returns to the results with the query and the selected row restored. Commands and settings have no actions, ⌘K does nothing there.

Actions, in order, with the keys that also work from anywhere in the list shown in tertiary ink: Open Menu ↩, Show in Menu Bar ⌘↩, Move to Visible / Hidden / Always Hidden (the current section is left out, and so is every move for the clock and Control Center, which macOS pins; a move lands at the chevron side of its section and is applied at once unless the editor holds other unapplied edits), Add a Shortcut… or Change Shortcut… (the current one trailing) and Remove Shortcut, Add Alias… or Edit Alias… (the current one trailing), Open and Quit for third-party apps (Quit is `NSRunningApplication.terminate`, only while it runs. A login-item helper named for its parent app opens the parent and quits under its own name, `ItemMenuActions.app`), Forget. A not-running launcher has Open and Forget. Forget only shows when there is a pick to drop.

- **Move** calls `AppState.moveItem(_:to:before: nil)`, the editor's drop between sections. Membership (`sectionModel.assignments`) changes and `engine.setModel` converges the assertion at once, so the icon hides or shows now; only its drawn position waits for Apply, like any between-section drop (the Menu Bar tab shows the pending change).
- **Add a Shortcut** is an inline row that records at once (⎋ cancels). A combination is refused, with the reason and what to do in the row, when it is one of Pelmet's own shortcuts, another item's, an edit shortcut (⌘A, ⌘C, ⌘V, ⌘X, ⌘Z, ⇧⌘Z), macOS's (`SystemShortcuts.owns`), or taken by another app (`RegisterEventHotKey` said no). It stays in the recording row so the next try is one keystroke.
- **Alias** is an inline text field row; ↩ saves, empty removes.
- Rows of items with a shortcut show it trailing, the way a command palette shows key equivalents.

## Smart search

Pure code in `PelmetCore` (`swift test`), no AppKit.

- **Corpus per item:** item title (AX title / identifier / description, the same names the editor uses), localized app name, a built-in synonym table (wifi, bt, vol, batt, dnd, vpn, kb, cc… localized), the user's alias, and the queries that led to it.
- **Match:** case- and diacritic-insensitive fuzzy, scored for consecutive letters, word starts and acronyms ("ccd" → Control Center Display), best of all match paths.
- **Rank:** match score × section weight (hidden and always hidden above visible: you search for what you can't see) × frecency (recency-weighted opens, about a month of memory) + query latch (a typed prefix you picked twice for the same row goes to the top).
- **Storage:** history in `app.fif7y.Pelmet.search.v1`, never inside the settings blob; Settings › General › "Reset Search History" (disabled, with the reason in its caption, while there is nothing to reset). Aliases and shortcuts are the user's own data, not history: `settings.itemAliases` and `settings.itemHotkeys` (`[String: …]` keyed by the item's `sectionKey`, absent in older blobs and decoded field by field like the other additions), so a reset leaves them.
- **Budget:** under 2ms per keystroke for 60 items and 100 setting rows.

## Beyond v1, ranked by value for the cost

1. **⌘K actions (in v1).** Move to Shown / Hidden / Always Hidden (membership only, so nothing moves in the bar), set a shortcut for this item, alias, open or quit the app.
2. **Per-item shortcuts (in v1, via the actions).** One `HotkeyManager` slot per item that opens its menu directly: raw ids from `HotkeyManager.itemSlotBase` (100) up, handed out by `AppState.syncItemHotkeys()` at launch and on every settings change, the hotkey calls `openItemMenu`.
3. **Search inside menus.** When an item's menu opens, Pelmet reads its rows over AX and remembers their titles. "pause sync" then finds "Dropbox › Pause Syncing", opens that menu and presses the row. Spike first: whether third-party status menus expose their rows (NSMenu should; window-style popovers expose a window tree instead). Menu titles can carry personal text, so the index stays local, forgettable per item, and skips password managers.
4. **Shortcuts and Spotlight.** An App Intent "Open menu bar item" with an item entity query, plus `pelmet://open?item=…`. Spotlight on 27 surfaces intents, and launchers can drive Pelmet without a second palette.
5. **Type in the tray.** When the floating tray is open, typing filters its cells. The tray is the visual way in, the command bar the keyboard one, same panel recipe.

Left out on purpose: calculator, clipboard history, web search. Other apps own those.

## Engineering

- **Prerequisite: lift the tray's press relay onto `roster`.** `TrayPress` on `floating-bar` already does one-item reveal → shielded HID click (AX press where it works) → shown oracles → kept revealed until the menu is gone → conceal. Becomes a shared `ItemPress` both surfaces call. Pelmet's own extras skip the relay: `ItemPress.pressOwn` runs the extra's own action (`ExtrasManager.activate`), after opening its section when a menu has to anchor on the item.
- **New (as built):** `Packages/PelmetCore/Sources/PelmetCore/Search/{FuzzyMatcher, FoldedText, SearchCandidate, SearchRanker, SearchHistory, Synonyms}.swift` + `SearchTests` (the matcher is `FuzzyMatcher`, rows are `SearchCandidate`, scoring is `SearchRanker`; there is no `ItemMatcher`). In the app: `Pelmet/Panels/GlassPanel.swift` (the recipe, shared with the tray), `Pelmet/CommandBar/{CommandBarController, CommandBarCorpus, CommandBarActions, CommandBarView, CommandBarField, SettingsIndex}.swift`, `Pelmet/App/ItemNaming.swift` (the editor's names, now shared). `SettingsIndex` lives in the app target because the panes are SwiftUI and carry no registry to read. `HotkeyManager.Slot.search`, right-click menu item, strings through `scripts/gen-xcstrings.py`.
- **Names for concealed items:** the corpus is `AppState.editorItems(in:)` for all three sections, so a name is the one the editor shows (concealed items that left the AX tree, stored keys and own extras included) and there is no store of last-seen names. Never "Item-0": `ItemNaming` falls back to the app name, then the bundle's last component.
- **Reuse:** `FuzzyMatcher` ranking (exact › prefix › word prefix › acronym › scattered) replaced the `SymbolCatalog.search` seed; `SettingsWindowController.show(tab:)` plus `AppState.settingsFocusRow` for the Settings jump; `ShortcutRecorder`'s key naming and `SystemShortcuts` for the shortcut row (the recording itself is the panel's, so it cannot race the panel's key monitor).
- **Accessibility:** field stays focused, ↑↓ move the selection, rows labeled "Wi-Fi, hidden", result count announced. Test with VoiceOver and Full Keyboard Access on.
- **Log prefix:** `search:` with timings for open, keystroke and press, so the budgets are read from the log, not guessed. The panel's window is placed once per open at its tallest (field + 8 rows) and only the glass in it changes height: resizing the window waited on the window server for 5–31 ms a keystroke, so `fit` should read ~0. The clear area under the glass passes clicks through. Rows are keyed by position, so a new ranking updates them in place. A keystroke logs `rank … (rank, apply, fit)` when it returns and `drawn, idle …` when the run loop has nothing left; the gap between the two is the SwiftUI update the keystroke queued.

## Verify

- Every section: visible, hidden, always hidden, an own extra, a launcher, the clock, a Control Center item, an overflowed item behind «.
- First keystroke typed within 20ms of the hotkey lands in the field.
- Return on a hidden item: 60fps burst, menu open under 400ms, no doubled icon, conceal after the menu closes.
- Arrow keys and type-select inside the opened menu.
- Esc returns focus to the previous app.
