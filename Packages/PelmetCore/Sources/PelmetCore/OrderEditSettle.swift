// OrderEditSettle.swift
// Which pending order edits the bar already satisfies, so they are no edit
// any more (AppState's `pruneSettledOrderEdits`): an icon dragged out of a
// section and back to its slot lit Apply for a zero-move pass (Timer,
// 2026-09-20 21:45). Pure: the app reads the bar and the walk.

import Foundation

public enum OrderEditSettle {
    /// The sections whose drawing the bar matches in full.
    ///
    /// - `bar`: canonical keys left to right, every icon the bar can place:
    ///   live frames, plus the remembered frame of a concealed icon
    ///   (`ApplyPass.rememberedFrames`).
    /// - `live`: the walk's icons; `concealed`: the engine's concealed set
    ///   (out of the AX tree, still on the bar).
    /// - `ownBehindOverflow`: own items (canonical keys) the last walk that
    ///   saw them live found behind the «.
    /// - `ownExtras`: Pelmet's extras (canonical keys) that are on the bar
    ///   whenever their section is out: not idle, whatever the walk sees.
    /// - `itemsPredateSwap`: the snapshot was stamped at a swap on the walk
    ///   before it (`EngineSnapshot.itemsPredateSwap`).
    public static func settledSections(
        _ edits: OrderEdits, bar: [ItemID], live: Set<ItemID>, concealed: Set<ItemID>,
        ownBehindOverflow: Set<ItemID> = [], ownExtras: Set<ItemID> = [],
        itemsPredateSwap: Bool = false, roster: Roster
    ) -> Set<Section> {
        // A swap stamps the mirror on the walk before it: the icons it just
        // revealed have left the concealed set and are not walked yet, so
        // they read as off the bar. Judged there, a drawing compared over
        // what was left: Shortcuts reordered in a concealed Hidden, and the
        // edit cleared the moment Hidden came out (live test, 2026-10-13).
        // The walk behind the swap lands within ~200ms and judges instead.
        guard !itemsPredateSwap else { return [] }
        // Pelmet's own items hide by their own visibility. One a helper drew
        // once and let go stays in the concealed set with no frame (helper
        // bundles are never pruned as stale): counted, its section stayed
        // pending and Apply lit for good. Like an idle extra, it is on the
        // bar where it is live or a frame remembers it, or where it was last
        // seen behind the « (no frame is remembered there, and a reorder of
        // only that separator cleared at once).
        // An extra that is not idle is on the bar all the same: concealed
        // with its section it is neither live nor in the concealed set, and
        // a reorder of Shortcuts in a concealed Hidden cleared at the drop,
        // past the crossing guard below too (live test, 2026-10-13).
        let placed = Set(bar)
        let onBar = Set(live.map(\.sectionKey)).union(ownExtras).union(
            concealed.filter { id in
                !(id.bundleID.map(PelmetBundle.ownIDs.contains) ?? false)
                    || placed.contains(id.sectionKey) || ownBehindOverflow.contains(id.sectionKey)
            }.map(\.sectionKey)
        )
        // Relative order says nothing about the chevron: an icon drawn into
        // Hidden but still on the Visible side matched its drawing, the edit
        // cleared before the grouper ran, and it went to the chevron end
        // instead of its drawn slot (vorssaint, Snib, 2026-10-07). A drop
        // between sections stays unsettled until a pass lands it
        // (`previousSection` cleared), so its section's drawing waits.
        let crossing = Set(edits.previousSection.keys)
        var settled: Set<Section> = []
        for (section, allDrawn) in edits.order {
            // An icon not on the bar at all (its app not running, an idle
            // extra) is no edit, as Apply drops it (`dropAbsentSkips`):
            // counted, it kept the drawing pending and Apply lit after the
            // grouper had placed everything (Today, Figma, four idle
            // separators, 2026-10-07).
            let drawn = allDrawn.filter { onBar.contains($0.sectionKey) }
            let drawnSet = Set(drawn)
            guard drawnSet.isDisjoint(with: crossing) else { continue }
            let placed = bar.filter { roster.section(of: $0) == section }
            // A drawn icon the bar cannot place (behind the «, or concealed
            // and never framed since launch) is exactly what the edit is
            // about: it stays pending until a pass can reach it. Counted
            // absent, a reorder in a section not revealed since launch
            // compared nothing with nothing and cleared, and Apply never lit
            // (Always Hidden, 2026-10-13; Velja, Pure Paste, Unclutter,
            // DBngin, 2026-09-21; Battery, Wi-Fi, 2026-10-12).
            // An extra its concealed section hides has no frame but holds its
            // model slot: drawn back to the order the edit started from
            // (dragged out and back), it is no edit, where waiting for a
            // frame lit Apply until the next reveal (review, 2026-10-13).
            let unplaced = drawnSet.subtracting(placed)
            if !unplaced.isEmpty {
                guard unplaced.isSubset(of: ownExtras),
                      edits.previousOrder[section]?.filter({ onBar.contains($0.sectionKey) }) == drawn
                else { continue }
            }
            if placed.filter(drawnSet.contains) == drawn.filter({ !unplaced.contains($0) }) { settled.insert(section) }
        }
        return settled
    }
}
