// OrderFromBar.swift
// The editor owns the order (vault plan "Dimble editor owns the bar order",
// 2026-10-20), and two things still come from the bar. An icon its section's
// stored order doesn't list yet takes the slot where it sits (M4): a new
// app's icon is adopted where macOS put it, never dragged to the front of
// its section. And each section's stored order is taken from the bar once
// after the update (M5), so the order keeper never rearranges a bar to an
// order nobody drew. Pure: the app hands it the (remembered) primary bar.

import Foundation

extension SectionModel {
    /// Lists every icon on `bar` (left to right, canonical keys) that its
    /// section's stored order doesn't: after its nearest listed left
    /// neighbour of the same section on the bar, else before the nearest
    /// listed right one, else last. Neighbours are looked for on the icon's
    /// own side of `chevron`: one of its section sitting across it is a
    /// stray, not a slot. Left to right, so icons that arrived together
    /// keep their order. A stale entry in another section's order goes.
    /// `exempt` icons (Pelmet's own, those behind the «) are left alone.
    /// Returns the icons slotted.
    @discardableResult
    public mutating func slotUnlisted(bar: [ItemID], chevron: ItemID? = nil, exempt: Set<ItemID> = []) -> [ItemID] {
        let roster = roster
        let split = chevron.flatMap { bar.firstIndex(of: $0) }
        var slotted: [ItemID] = []
        for (i, id) in bar.enumerated() where !exempt.contains(id) && id != chevron {
            let home = roster.section(of: id)
            var list = order[home] ?? []
            guard !list.contains(id) else { continue }
            let listed = { (other: ItemID) in roster.section(of: other) == home && list.contains(other) }
            let side = split.map { i < $0 ? 0..<$0 : ($0 + 1)..<bar.count } ?? bar.indices
            if let left = bar[side.lowerBound..<i].last(where: listed), let at = list.firstIndex(of: left) {
                list.insert(id, at: at + 1)
            } else if let right = bar[(i + 1)..<side.upperBound].first(where: listed), let at = list.firstIndex(of: right) {
                list.insert(id, at: at)
            } else {
                list.append(id)
            }
            for other in order.keys where other != home { order[other]?.removeAll { $0 == id } }
            order[home] = list
            slotted.append(id)
        }
        return slotted
    }

    /// The section's listed icons that `bar` shows, re-sorted into the bar's
    /// order among their own slots. The rest keep theirs. True if it changed.
    @discardableResult
    public mutating func foldBarOrder(of section: Section, bar: [ItemID]) -> Bool {
        guard var list = order[section] else { return false }
        let roster = roster
        let position = Dictionary(bar.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let slots = list.indices.filter { position[list[$0]] != nil && roster.section(of: list[$0]) == section }
        let sorted = slots.map { list[$0] }.sorted { position[$0]! < position[$1]! }
        for (k, slot) in slots.enumerated() { list[slot] = sorted[k] }
        guard list != order[section] else { return false }
        order[section] = list
        return true
    }
}
