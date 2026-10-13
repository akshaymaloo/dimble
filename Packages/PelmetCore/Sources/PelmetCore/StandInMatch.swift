// StandInMatch.swift
// MenuBarAgent draws real buttons only on the active display's bar (the one
// the frontmost app is on). Every other bar shows a stand-in group per icon,
// and each group nests the owning app's whole extras bar, so a group's own
// subtree cannot say which of the app's icons it is. Its place can: an app's
// groups on one bar, left to right, are its icons in the order the extras
// bar's items sit on the active bar. Named by the first title instead, every
// Pelmet stand-in on the main bar read as the chevron, the walk kept one,
// and Shortcuts, Media and Camera & mic were "not moved" for good (live
// test, 2026-10-13). Pure: the enumerator reads the frames.

import CoreGraphics

public enum StandInMatch {
    /// Which of the app's items each stand-in group is: for each entry of
    /// `groups` (the minX of each of one app's groups on one bar), the index
    /// into `items` (the minX of each item on the app's extras bar, nil
    /// without a frame), or nil where position cannot tell. Counts that
    /// differ, or an item with no frame, leave every group unnamed; groups
    /// or items that share an x leave only those unnamed.
    public static func items(forGroupsAt groups: [CGFloat], itemsAt items: [CGFloat?]) -> [Int?] {
        var result = [Int?](repeating: nil, count: groups.count)
        let itemXs = items.compactMap { $0 }
        guard groups.count == items.count, itemXs.count == items.count else { return result }
        let groupOrder = groups.indices.sorted { groups[$0] < groups[$1] }
        let itemOrder = itemXs.indices.sorted { itemXs[$0] < itemXs[$1] }
        for rank in groupOrder.indices {
            let group = groupOrder[rank], item = itemOrder[rank]
            guard !sharesX(groups, at: group), !sharesX(itemXs, at: item) else { continue }
            result[group] = item
        }
        return result
    }

    /// Half a point apart or less: one spot, as far as order goes.
    private static func sharesX(_ xs: [CGFloat], at index: Int) -> Bool {
        xs.indices.contains { $0 != index && abs(xs[$0] - xs[index]) <= 0.5 }
    }
}
