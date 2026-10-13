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
    /// - `onBar`: canonical keys of every icon on the bar at all, live or
    ///   concealed (out of the AX tree, still on the bar).
    public static func settledSections(
        _ edits: OrderEdits, bar: [ItemID], onBar: Set<ItemID>, roster: Roster
    ) -> Set<Section> {
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
            guard drawnSet.isSubset(of: Set(placed)) else { continue }
            if placed.filter(drawnSet.contains) == drawn { settled.insert(section) }
        }
        return settled
    }
}
