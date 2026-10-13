# 0.3.2 review fixes

Max-effort review of the whole 0.3.2 cycle (`3f757c96a..d7fa2e5`, roster vs main), Tue Oct 13. 16 finders,
9 verifiers, one gap sweep. Scope decided by Gab: **everything** (all confirmed/plausible bugs plus the cleanup
and efficiency items) before the Mon Oct 19 stable; beta.6 (build 68) first, on Gab's "cut" only.
Focus decision: **upgraders keep their bars** (see B5 · REM-1).

Line numbers are HEAD `d7fa2e5`. IDs are the review's. Each item: bug → fix direction → check.

## How a batch runs

- One batch = one worktree branch off `roster`, one worker, one local commit. Never push.
- Build: `xcodegen generate` (the .xcodeproj is gitignored), then
  `xcodebuild -project Pelmet.xcodeproj -scheme Pelmet -configuration Debug build`. Pure logic: `swift test` in
  `Packages/PelmetCore` / `Packages/PelmetEngine`. Never `xcodebuild test` (launches a second Pelmet), never
  launch or install the app: the main session installs after review.
- Pure logic that a bug lived in moves into PelmetCore with a test when it's cheap to (APP-1, PKG-1, PANEL math).
- Strings: edit `scripts/gen-xcstrings.py` (source of truth, 10 languages) and run it, never hand-edit
  Localizable.xcstrings. `Text(stringVar)` doesn't localize.
- Add a log line for every new refusal/gate ("log the reason before gating").
- A reviewer agent reads each batch diff before merge; then install + log oracles + Gab's live list.

## B1 · Ordering, grouping gate, overflow (AppState, ApplyPass, SectionGrouper, EditorDragSession)

- **APP-1** `AppState.swift:2670` pruneSettledOrderEdits drops concealed icons with no remembered frame from
  `drawn`; since e2e3c07 concealed icons never get one, so a reorder in a never-revealed section compares
  `[] == []` and is cleared (Apply never lights). → Any drawn item the bar can't place (not live, no remembered
  frame) keeps its section's edit pending (`continue`), restoring base semantics. Extract the settle decision to
  PelmetCore with tests: never-revealed AH reorder stays pending, partial-unseen stays pending, all-seen-matching
  clears. Fix the comment at 2674-2679. Check: relaunch, reorder two Always Hidden icons → Apply (1) lights.
- **APP-2 + SIMP-1/ALT-2/APP-3** `AppState.swift:2486/2498`, `ApplyPass.swift:376/381` the grouping gate
  ignores a reveal the user holds (hotkey panel/bar, icons out alone) and `transitions.passInFlight`; a strays
  pass reveals via the bar (closes the panel) and conceals in its defer. → One "bar at rest" predicate (single
  `fluxReason: String?`) read by barInFlux, groupingGate and noteOverflow: passInFlight / quiet apply hold,
  press holds, transitioning, applying, relays, panel open, any user-held reveal or shown-alone items. Grouping
  runs only from a fully concealed, idle bar. Log the reason. Check: hotkey-open panel + stray ready + 2s idle →
  panel stays, log shows the defer.
- **APP-4** `AppState.swift:3305` overflowTrappedItems only assigned after `guard trapped !=
  overflowTrappedCount`. → Assign the list before the count guard (or compare sets).
- **ALT-4** `AppState.swift:3265` Apply / press relay expand the « and feed noteOverflow a 0 that resets the
  notice at once. → Skip overflow reads while the « is expanded by us (same predicate as above).
- **ALT-3** `ApplyPass.swift:39-56,116` the own-extra-on-chevron and linger filters only feed noteOverflow;
  primaryFrames runs overflowTrapped unfiltered (EditorItemsBuilder.swift:182 too). → One "drawn now" filter
  applied before trapped detection everywhere.
- **XF-5** `ApplyPass.swift:225` `known` misses concealed system items (Sound) that the engine prunes from
  `concealed`, so the ledger forgets a by-hand placement. → Include model-assigned running items in `known`.
- **SET-5** `Settings/EditorDragSession.swift:35,51-58` static `anyActive` only cleared by `end()`, watcher holds
  the session weakly. → End on deinit / MenuBarTab onDisappear, and treat as inactive when
  `NSEvent.pressedMouseButtons == 0`.
- **SYS-6** `AppState.swift:2581-2593` restoreFocus pulls focus back if the user switched apps within ~400ms. →
  Remember the pid the drag activated; restore only if it is still frontmost.
- **EFF-7** `SectionGrouper.swift:199` + gate order: cheap checks first (input idle, display asleep, locked), the
  two CGWindowList reads last; wait on wake/unlock notifications instead of 2s polling while asleep/locked.
- **ALT-5** (cleanup) `AppState.swift:2271/2500/3270` "bar attached" recomputed 3 ways with different nil
  handling. → One `barAttached` property.

## B2 · Panel (PanelPresenter, PanelView, PanelPane, GlassPanel, PanelDragGhost, ItemPictures)

- **PAN-1** `PanelPresenter.swift:203,671` .statusItem/.barDrag opens use `drawnChevron()?.screen` (the one
  display hosting the button window). → Open on the pointer's screen for every reason (same approach as
  PelmetStatusItem's #26 context-menu fix). Check on an external display: chevron click, Show All, ⌘-drag.
- **PAN-4/REUSE-1** `PanelPresenter.swift:688-695`, `GlassPanel.swift:146-151` 24pt fallback when visibleFrame
  has no band (externals have a 30pt bar). → One bar-band helper reading the real bar window (PelmetStatusItem
  `underBar` / layer-24 bar window), used by barBand/top/heightCap, GlassPanel.topUnderBar and drawnChevron
  (same band rule as MenuBarBandMonitor.liveChevronMaxX).
- **PAN-2** `PanelPresenter.swift:978` (merge at 919) Row layout merges everything into one `.hidden` block, so
  Didn't-fit keys land in `missing` → useless passes every open / every 15 min. → Track Didn't-fit keys from the
  model, not `block.kind`.
- **PAN-3** `PanelPresenter.swift:1695,727` after an Always Hidden open the fold is forced open but the fold tile
  and menu check still look live; "As you left it" silently persists. → Folding clears the AH request and folds;
  persist only real changes.
- **REUSE-2** `PanelPresenter.swift:1003` standIn skips the system-glyph fallbacks (#19 blank square for
  Siri/Time Machine). → Share the TileGlyph / CommandBarCorpus.glyph(for:) chain.
- **PAN-6** `PanelPresenter.swift:227,1331` picture pass runs on .barDrag opens and fold springs during a bar
  ⌘-drag. → No pass while a bar drag is in flight (presenter side; the TC guard is B5).
- **PAN-5** `PanelPresenter.swift:1553-1559` column drag relies on `onEnded` only. → Mouse-up fallback like the
  tile drag; reset `columnsTip` on close.
- **DUI-5** `PanelPresenter.swift:1694` toggleFold has no `isOpen` guard. → Guard.
- **PAN-7** `PanelPresenter.swift:1149/1426` ghost home is left-relative on a right-anchored panel, read before
  the restoring refresh. → Right-relative or read after refresh.
- **PAN-8** `PanelPresenter.swift:405-438` close() never calls stopGlass(). → Call it.
- **WRAP-3** `ItemPictures.swift:28-37` non-monochrome pictures survive a light/dark switch. → Drop them on
  appearance change (or key by appearance).
- **DUI-6** `PanelPresenter.swift:330` screen-parameters observer token discarded. → Store it.
- **EFF-3** `PanelView.swift:148,182,484` root `@State hovering` re-renders the whole panel; every body builds
  every tile's context menu (corpus scan, runningApplications, ~8 String(localized:)). → Hover state in a child
  view; per-tile app looked up once in buildContent; menus built on demand.
- **EFF-4** `PanelPresenter.swift:210,858` editor board built 6× per open. → One build per open, shared by corpus
  and model.
- **EFF-5** `PanelPresenter.swift:1538-1540` (+ `PanelPane.swift:417`) settingsChanged() at every column step
  swaps status item images. → Write columns + refresh during the drag, settingsChanged once on end; key-based
  skip in PelmetStatusItem.applyImage.
- **EFF-6** `PanelPresenter.swift:1090,1155-1158,1276-1296` tickDrag runs from the 60Hz timer and from
  onChanged. → One source, skip unchanged pointer, bar icons once per drag.
- **SIMP-3** `PanelPane.swift:433` preview copies the presenter's key switch/setQuery/showTip/dragColumns (already
  diverged on Enter). → Share one implementation.
- **SIMP-4** `PanelPresenter.swift:209-213,815-820,842-846` corpus load ×3 + `corpusRead` flag (one copy skips
  history). → One `loadCorpus()`.
- **SIMP-5** `PanelPresenter.swift:1536` literals 2/10. → `PanelOptions.columnRange`.
- **SIMP-8** TileDrag.hit vs dragState.target (1051/1189/1510); release-guard trio + magic 0.35 (1100-1102,
  1405-1407); house easing curves copied ~10× (PanelPresenter, PanelPane, PanelDragGhost, SettingsView) → one
  set of constants; misplaced doc line TransitionCoordinator.swift:1688 (B5 if easier).
- **REUSE-7** `PanelPresenter.swift:1834` private NSScreen.displayID. → `NSScreen.directDisplayID`.
- **REUSE-3 (panel part)** `PanelPresenter.swift:994,1025` launcherIcon / launcher press. → Cached
  MediaControls.appIcon; CommandBarController.open (logs failures).
- **REUSE-5** `ItemPictures.swift:248` rgba/distance copies (ConcealGhostOverlay.swift:657,697,
  TransitionCoordinator.swift:1768) with different colour spaces and `d > 6`. → One helper. Last in batch;
  re-verify pictures live.

## B3 · Event taps (MenuBarBandMonitor, HoverTypingTap, BarDragRedirect)

- **XF-1** `MenuBarBandMonitor.swift:536` `!appState.pressRunning` drops every empty-bar click for the whole
  relay (up to 60s, pressMenuCap). → Drop only the relay's own posted click: filter on `SyntheticInput.tag`
  (ItemMover.swift:110; ClockClickRelay.swift:150 does it) if the global monitor's `cgEvent` carries the user
  data, else a short window around the posted click recorded by ItemPress. Log refusals. Check: open a hidden
  app's window via the panel, then click the empty bar → reveals.
- **EVT-2** `HoverTypingTap.swift:121` geometry-only: swallows typing meant for the command bar / a focused
  Settings field. → Disarm while any other Pelmet window is key (command bar, Settings), or close the hover panel
  when the command bar opens.
- **SYS-4** `HoverTypingTap.swift:115` autorepeat keyDowns + their keyUp swallowed → stuck keys. → Ignore
  `keyboardEventAutorepeat`; swallow a keyUp only if its keyDown was swallowed.
- **SYS-5** `HoverTypingTap.swift:107-112` (`BarDragRedirect.swift:131`) tapEnable(false) outside the lock. →
  Inside the lock, or re-check `armed`.
- **REM-3** `MenuBarBandMonitor.swift:363` band-exit adoption fallback skipped when panelDropZone is armed. →
  Keep a fallback in panel mode (end the drag on band exit when no mouse button is down).
- **EFF-8** `MenuBarBandMonitor.swift:179-183` + `PanelPresenter.swift:1504-1507` dropZones ×3 and
  orderFrontRegardless per drag event. → Once per event; order the ghost front once.
- **liveChevronMaxX** `MenuBarBandMonitor.swift:771` NSScreen.screens back on the per-move path. → Cached
  screens.
- **REUSE-6** `HoverTypingTap.swift:70`, `BarDragRedirect.swift:84` copied tap scaffolding (thread, run loop,
  re-enable) and Cocoa→CG flips ×5. → One EventTap helper shared with PointerMoveTap/ClockClickRelay. Last in
  batch.

## B4 · Settings, Search, command bar, strings

- **SET-1** `ShortcutRecorder.swift:114` keyDown monitor has no window/focus check and keeps recording when focus
  moves; ⌫ clears; ⌘A etc. become global hotkeys. → Stop recording on any click outside the chip, focus change or
  window resign; only handle events for the recorder's window; refuse standard edit chords (⌘A/C/V/X/Z) as item
  hotkeys. One recorder records at a time.
- **SET-4** `SearchPane.swift:351` alias @State read only onAppear; blur writes stale text back. → Re-sync from
  settings when not focused; write only if the user edited since focus.
- **SET-3** `SearchPane.swift:370-379` no save on disappear. → Commit edited text on onDisappear.
- **SET-2** `SettingsView.swift:1092` (+ `AppState.swift:275`) picker shows nearest of 0/1/2/3/5 while stores keep
  0.5 steps; re-picking the shown item is a no-op. → Snap stored values to the menu's options at load (one-time),
  and let PelmetMenuPicker write on re-pick.
- **SET-6** `SettingsView.swift:1478,1487` installed banner opens the newer available version's notes. → The
  request carries the installed version; clear the "installed" notification once acted on.
- **SET-7** `SearchPane.swift:164` ForEach id is sectionKey (duplicates for two-icon apps). → Full item id.
- **L10N-1** `CommandBar/SettingsIndex.swift:85,92` stale titles ("Always Hidden fold", "Search history") vs rows
  "Opens from" / "Search learns what you open". → Rename; old words as keywords.
- **SWEEP-2** `SearchPane.swift:99` "Any setting" probes "Hover delay", which no longer exists (dead in 9
  languages). → Probe a title that exists in every language ("Reveal on hover").
- **SWEEP-1** `App/ItemMenuActions.swift:69`, `CommandBarCorpus.swift:96` Quit titles/subtitles use raw
  appName (bundle-id names like "85C27NK92C.com.flexibits…"). → Same usable-name path as ItemNaming.displayName.
- **SWEEP-3** `App/ItemNaming.swift:110,125` shippingAppNames caches nil forever. → Cache hits only.
- **SIMP-6** `CommandBar/CommandBarActions.swift:62-97` duplicates ItemMenuActions; "Set Shortcut…" vs "Add a
  Shortcut…". → Route through ItemMenuActions, one wording.
- **L10N-2** `MenuBarTab.swift:662` tooltip says "System Settings › Control Center" → "› Menu Bar".
- **L10N-3** `scripts/gen-xcstrings.py:202-203` ru "В строке меню" among bare nouns; title lost "in". → Fix ru.
- **L10N-4** `CommandBarController.swift:939` strip "…" then trim whitespace (German " …").
- **EVT-6** `Update/ReleaseNotesView.swift:48,74` scrollHeight measured against a 120pt quirks-mode viewport. →
  DOCTYPE + measure the body/wrapper so short notes size down.
- **REUSE-3 (settings part)** `SearchPane.swift:189` uncached icon lookup per render. → Cached helper.
- **REUSE-4** `ShowWhen.swift:71,36`, `App/ShowRules.swift:21` hardcoded symbols/IDs, exact-equality match. →
  CommandBarCorpus.symbol(for:), ItemID.status(...), MenuBarPolicy.systemItem(for:).
- **SIMP-8 (settings part)** `ShowWhen.swift:358` "Waits 5 seconds" → from ShowRules.wifiGrace;
  `ShowWhen.swift:233-236` use SettingSwitch.

## B5 · Pictures, show rules, press, clock, Focus (TransitionCoordinator, ConcealGhostOverlay, ShowRules, MediaControls, ItemPress, AppState)

Runs after B1 merges (both touch AppState).

- **REM-1** `AppState.swift:277-294`, `Extras/MediaControls.swift:486-489` Focus migration inverts "only while
  active". Decision: upgraders keep their bars. → New one-shot migration key: every Focus in Hidden/Always
  Hidden gets `.whenActive` (new `.whenActive` = section reveal OR active = 0.3.1's default behaviour). Covers
  0.3.1 upgraders and beta.5 testers the old migration flipped. Time Machine mapping unchanged. Fix the comment.
  New installs keep the new opt-in default. Release-notes line.
- **WRAP-2/SYS-1** `AppState.swift:752-754` show rules call engine.setRuleShown directly: idle/strip pictures go
  stale (Battery blinks out / ghosts for up to 900s), pass guards check only itemsInBar. → Route through
  TransitionCoordinator: drop the idle picture on a rule change and count rule-shown items in the pass/strip
  guards.
- **WRAP-1** `PanelPresenter.swift:1771-1777` (TC 1388-1392, 1458, 1505-1513) every wanted-but-missing key
  stamped unpicturable for 900s, even when follow-up rounds were skipped or the empty-bar picture failed. →
  picturePass reports per-key outcome; stamp only keys attempted and failed in an informative pass.
- **ALT-1** `Press/ItemPress.swift:158`, root `AppState.swift:3164` / ConvergePlan.swift:108 `snapshot.concealed`
  = live ∪ carried loses icons a pass pushed behind «. → Build `concealed` from model assignments of running
  bundles (as `concealable` is), so presses and presence checks keep them.
- **APP-6** `TransitionCoordinator.swift:582-587` all items released before the reveal ran → still settles
  `.revealed([], .itemInBar)`. → Settle back to concealed.
- **XF-3** `TransitionCoordinator.swift:1362-1382` first pass round lacks the press-hold guard. → Defer the pass
  while a press holds the bar (and while a bar drag is in flight, PAN-6).
- **APP-5** `AppState.swift:1540-1551` NC probe takes a user close within 0.8s as "press dead", persists it for
  the build, replays a click that reopens NC. → Ignore samples with user input since the press; require two
  samples before persisting; never replay after a user close.
- **APP-7** `AppState.swift:872` clock branch skips the passInFlight wait. → Same wait as other presses.
- **SYS-2** `App/ShowRules.swift:183-188` Wi-Fi grace sleeps on ContinuousClock across system sleep. → Restart
  the grace on wake (NSWorkspace.didWakeNotification); decide against the current link state.
- **EFF-1** `ConcealGhostOverlay.swift:395-398` SCShareableContent lookup per display per frame. → Once per pass.
- **EFF-2** `ConcealGhostOverlay.swift:353`, `TransitionCoordinator.swift:1658-1666,1723-1726` passes capture every
  display but cut only the primary; pixelsApart maxes over side strips. → Primary-only capture for passes. (Check
  `iconsOnly` returning nil when a side strip lacks a background.)
- **EFF misc** `pixelsApart` re-decodes the previous strip (TC:1666); `flatMask` redraws twice on capsule
  failure (ItemPictures:116, B2 if easier); `invalidateShadow()` every 120Hz fold step (GlassPanel:128, B2).
- **SIMP-2** `TransitionCoordinator.swift:1382` passInFlight/quietApplyInFlight/passHasWaiter/pressBegan reset by
  hand in four exits. → One hold enum with begin/end.
- **SIMP-7** `AppState.swift:2978` `pelmet.debug.panel` override still beats `settings.hiddenIconsIn`. → Remove;
  the debug toggle gets its own key.

## B6 · Engine + core (PelmetEngine, PelmetCore)

- **PKG-3** `AgentBarEngine.swift:462-481` empty-walk retry every 2s forever (≈14k AX walks overnight while
  locked). → Back off (2→4→…→60s) and stop on lock; restart on unlock/wake.
- **PKG-1** `StrayLedger.swift:104` (+:93) relaunch standing settled on a side-nil look; nil→side skipped. → Only
  settle when the side is known and in place. Test.
- **REUSE-8** `ShowRuleSettings.swift:51`, `PanelOptions.swift:78`, `SettingsStore.swift:507` forgiving
  per-field decoder copied ×3. → One helper.
- PanelGrid.swift:194 `panelSize` used only by tests: leave unless trivial.
- PKG-6 (`HotkeySpec.off` as keyCode .max breaks a manual downgrade to 0.3.1): not fixable from 0.3.2, note only.

## B7 · Docs + site (main session)

- **EVT-5** `docs/RELEASE.md:50-51` says deltas go to gh-pages; release.sh attaches them to the release. Fix doc.
- **CONV-1** README.md:92,98,99 hotlinks panel.gif + settings-panel-{light,dark}.png that 404 until pelmet-site
  `panel-block` deploys. Deploy the site with the stable, before or with the roster → main merge.
- pelmet-site `CREDITS.md` doesn't cover the third-party glyphs in `assets/settings-panel-{dark,light}.png`
  (licensing rule). Add the row.
- Design note for Gab (not a bug, ALT-8): Show in Menu Bar gives 4s to reach the icon at Instant but only 1s at
  "After 1 second".

## Refuted (don't fix)
ALT-5 (as a bug), ALT-7, XF-4 (by design, 1c3c70a), ALT-8 (intended), PKG-2, PKG-4, PKG-5.

## Landed (2026-10-13, roster 99653bf)

B6 eba8ec6..5859dcb · B3 227108f · B1 23d2a80, 3559534, af3ad35 · B4 3e036c0 · B2 7bcbec6, bccb8b4, 82de724 ·
merge fix 7424aea · B5 7d75ae2..99653bf · docs fd4033b. Every batch had a fresh-eyes review plus a re-check of
its fixes. Skipped on purpose: REUSE-6, SIMP-3, EFF-4 (needs a board cache), REUSE-5 in ConcealGhostOverlay
(calibrated thresholds), WRAP-3's wallpaper-ink case. Known trade-offs: tagged test clicks (`tagclick`) no longer
reach the empty-bar trigger; saved auto-hide delays snap to the menu's values (0.5s → 1s); beta.5 testers who set
Focus to section-only get "while active" once; after a pass on an always-show display Hidden conceals and comes
back (one blink); a show-rule icon's own tile and the 1–2 tiles over its concealed spot keep stand-ins while the
rule holds it out. Follow-up after the stable: a failed press drops a real icon's tile (pre-0.3.2).

## Live checks (installed build, grep pelmet.log)

Boot: `start: axTrusted`, `own items adopted`, `helpers:` lines with fresh pids, `migrate: focus keeps its bar`
(once, only if a Focus sat in Hidden/Always Hidden).

- **Lock/wake (B6):** lock 2+ min, unlock. `converge: AX walk empty, screen locked — retries stop until unlock or
  wake`, then `converge: screen unlocked after Nms of empty walks — retrying`; no walk every 2s while locked.
- **Press relay (B3):** press an icon behind the « from the panel. While its menu is up, click empty bar:
  `band: click refused — a press relay holds the « open`. Bar must not toggle mid-relay.
- **Typing (B3/B5):** hover-open the panel, then ⌘K or focus a Settings field and type: letters stay there
  (`panel: typing over the hover panel stays with …`). With Settings in front and nothing focused, typing still
  searches the panel.
- **⌘-drag to panel (B3/B2):** ⌘-drag an icon from the bar onto the open panel and let go fast: it lands
  (no `endPanelDrop` without a drop).
- **Grouping (B1):** reorder a Hidden icon in the editor while that section was never revealed since launch:
  Apply lights. Display set to always show: drop an icon on the wrong side, `group: relocating …` runs, then
  `displays: pass over — back to the policy's reveal, state=…` (Hidden blinks once, Always Hidden goes away).
- **Didn't fit (B1):** with icons behind the «, after a picture pass or a Camera & mic press:
  `overflow: reading the bar the hold left`; the editor's note is current.
- **Shortcuts (B4):** record a shortcut: ⌘A/C/V/X/Z are refused; a second click on the chip cancels; ⎋ cancels;
  ⌫ removes. Old edit-chord icon shortcuts are dropped at launch (one log line).
- **Open/Quit (B4):** right-click a helper-owned icon (Fantastical): Open launches Fantastical, Quit names the helper.
- **Panel display (B2):** hover the external display's bar: the panel opens there
  (`panel: on display N (the pointer's), bar 30pt`). Hotkey with an app full screen on the external: read the
  same line, must not hang over the app. Hotkey with Settings on the external and the pointer off any bar: opens
  on the primary display.
- **Always Hidden fold (B2):** ⌥-click to open Always Hidden in the panel, fold it, then ⌥-click again: it comes
  back (`put away ["alwaysHidden"] state=…`).
- **Show rules (B5):** Battery on "On battery", unplug: the bar pictures retake (`cover: a show rule changed the
  bar`), no ghost Battery; open the panel, new tiles still picture
  (`pass: N where a show rule's icon sits on the empty bar, not cropped`).
- **Wi-Fi grace (B5):** Wi-Fi rule on, sleep the Mac with Wi-Fi dropping: on wake
  `rule: Wi-Fi grace ran across sleep, starts over on wake`.
- **Clock / NC (B5):** press the clock during a picture pass: `clock: waits for the picture pass`. ⌥⌘N twice
  closes Notification Center for good; closing it yourself: `closed by the user — not counted, no replay`.
- **Behind the « (B5):** full reveal, conceal, then press an icon that sat behind the « (Velja) from the panel:
  it opens. Panel open with a tile that can't be pictured: `asked again next open`, no pass loop.
- **Picture pass cost (B5):** `pass: strip captured` reads `(1 display(s)` with an external attached; external
  bar copies still picture on reveal.
