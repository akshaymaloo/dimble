// ApplyCount.swift
// The number on the Apply button (AppState's `pendingMoveCount`): the moves
// a plan read off the collapsed bar finds, plus the drops it cannot see that
// a pass reaches anyway. Pure: the app reads the bar, the walk and the
// sections.

import Foundation

public enum ApplyCount {
    public struct Count: Equatable, Sendable {
        /// Dropped icons the plan could not see because the « holds them:
        /// the pass expands it.
        public var trapped: Set<ItemID>
        /// Dropped icons the plan could not see because their concealed
        /// section hides them: the pass reveals it.
        public var concealed: Set<ItemID>
        public var total: Int
    }

    /// `plan` is read off the collapsed bar (remembered frames); `trapped`
    /// is every canonical key the walk puts behind the «, leftovers
    /// included; `drawn` and `concealed` judge one icon right now
    /// (`AppState.drawnNow`, `isConcealed`).
    ///
    /// Only an icon the person dropped counts beyond the plan's moves. A
    /// concealed one is never trapped, whatever its leftover frame overlaps,
    /// and the neighbour a drop lands beside is no move: read just after a
    /// conceal, Shortcuts dropped after Sound in Hidden counted both as
    /// behind the «, "Apply (2)" for one move (live test, 2026-10-13).
    /// A drawn icon really behind the « keeps the count at 1 at least: the
    /// plan without it can find nothing to do while the pass, expanding the
    /// « for it, drags the drop beside it (review, 2026-10-13).
    public static func count(
        _ plan: MovePlan.Plan, edits: OrderEdits, trapped: Set<ItemID>,
        drawn: (ItemID) -> Bool, concealed: (ItemID) -> Bool
    ) -> Count {
        let unseen = Set(plan.skipped.filter { $0.1 == .notOnScreen }.map(\.0)).intersection(edits.dropped)
        let hidden = unseen.filter(concealed)
        let behind = unseen.intersection(trapped).subtracting(hidden)
        let total = plan.moves.count + behind.count + hidden.count
        let drawnBehind = trapped.intersection(edits.order.values.joined()).filter(drawn)
        return Count(trapped: behind, concealed: hidden, total: total == 0 && !drawnBehind.isEmpty ? 1 : total)
    }

    /// Whether `id`'s concealed section is what keeps it off the bar right
    /// now. Drawn wins (an icon out on its own, one macOS will not hide);
    /// then the engine's concealed set (`concealedKeys`, canonical keys);
    /// then Pelmet's own extras, which the assertion never hides (they leave
    /// the layout by their own visibility, so the set never lists them):
    /// concealed while their section is out of view, unless idle (`wouldShow`
    /// false: off the bar whatever its section). Not the «: the walk just
    /// after a conceal still lists Shortcuts and Sound, leftovers on top of
    /// each other (live test, 2026-10-13).
    public static func isConcealed(
        _ id: ItemID, drawn: (ItemID) -> Bool, concealedKeys: Set<ItemID>,
        wouldShow: (ItemID) -> Bool, section: (ItemID) -> Section, revealed: Set<Section>
    ) -> Bool {
        let key = id.sectionKey
        if drawn(key) { return false }
        if concealedKeys.contains(key) { return true }
        guard MenuBarPolicy.isPelmetExtraID(key), wouldShow(key) else { return false }
        let home = section(key)
        return home != .visible && !revealed.contains(home)
    }
}
