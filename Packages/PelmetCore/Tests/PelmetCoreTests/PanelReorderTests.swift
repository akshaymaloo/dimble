import CoreGraphics
import Foundation
import Testing
@testable import PelmetCore

@Suite struct PanelReorderTests {
    private func t(_ i: Int) -> PanelTile { .item(.bundleKey("t\(i)")) }
    private func tiles(_ n: Int) -> [PanelTile] { (0..<n).map(t) }

    /// The frames the panel would lay out: 44pt tiles, 6pt gaps, `columns` wide.
    private func frames(_ tiles: [PanelTile], columns: Int = 3) -> [PanelTile: CGRect] {
        let grid = PanelGrid(tiles: tiles, columns: columns, layout: .panel, showsNames: false)
        return Dictionary(grid.rows.joined().map { ($0.tile, $0.frame) }, uniquingKeysWith: { first, _ in first })
    }

    /// The centre of the tile in `tiles` at `index`.
    private func centre(_ tiles: [PanelTile], _ index: Int, columns: Int = 3) -> CGPoint {
        let frame = frames(tiles, columns: columns)[tiles[index]]!
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private func slot(_ point: CGPoint, in list: [PanelTile], dragged: PanelTile, columns: Int = 3) -> Int? {
        PanelReorder.index(at: point, tiles: list, frames: frames(list, columns: columns), dragged: dragged)
    }

    // MARK: - Placing

    @Test func placingMovesATileAmongTheIcons() {
        let list = tiles(4)
        #expect(PanelReorder.placing(t(0), in: list, at: 2) == [t(1), t(2), t(0), t(3)])
        #expect(PanelReorder.placing(t(3), in: list, at: 0) == [t(3), t(0), t(1), t(2)])
        #expect(PanelReorder.placing(t(1), in: list, at: 1) == list)
        // A tile from another section goes in; clamped to the ends.
        #expect(PanelReorder.placing(t(9), in: list, at: 2) == [t(0), t(1), t(9), t(2), t(3)])
        #expect(PanelReorder.placing(t(9), in: list, at: 99) == list + [t(9)])
        #expect(PanelReorder.placing(t(9), in: list, at: -3) == [t(9)] + list)
    }

    @Test func launchersAndTheFoldKeepTheirPlaceAfterTheIcons() {
        let list = [t(0), t(1), .launcher("app.x"), .fold]
        #expect(PanelReorder.placing(t(0), in: list, at: 1) == [t(1), t(0), .launcher("app.x"), .fold])
        #expect(PanelReorder.placing(t(9), in: list, at: 99) == [t(0), t(1), t(9), .launcher("app.x"), .fold])
    }

    @Test func breaksAreSlotsLikeIcons() {
        let list = [t(0), t(1), .rowBreak, t(2)]
        // Just before the break: the end of the first group.
        #expect(PanelReorder.placing(t(2), in: list, at: 2) == [t(0), t(1), t(2), .rowBreak])
        // Just after it: the start of the second.
        #expect(PanelReorder.placing(t(0), in: list, at: 2) == [t(1), .rowBreak, t(0), t(2)])
    }

    // MARK: - The slot under the pointer

    @Test func theDraggedTileTakesThePlaceOfTheTileUnderThePointer() {
        let list = tiles(6)
        // Dragged forward it lands after the tile it is over...
        #expect(slot(centre(list, 2), in: list, dragged: t(0)) == 2)
        #expect(PanelReorder.placing(t(0), in: list, at: 2).prefix(3) == [t(1), t(2), t(0)])
        // ...dragged back, before it.
        #expect(slot(centre(list, 1), in: list, dragged: t(4)) == 1)
        #expect(PanelReorder.placing(t(4), in: list, at: 1).prefix(3) == [t(0), t(4), t(1)])
    }

    @Test func overItsOwnPlaceNothingMoves() {
        let list = tiles(6)
        for own in [0, 2, 5] {
            let at = slot(centre(list, own), in: list, dragged: t(own))
            #expect(at == own)
            #expect(PanelReorder.placing(t(own), in: list, at: at!) == list)
        }
    }

    @Test func settlesAfterOneMove() {
        // Once the tile has taken the place under the pointer, the pointer is
        // over the tile itself: the next read is a no-op, never a swap back.
        var list = tiles(6)
        let pointer = centre(list, 3)
        let first = slot(pointer, in: list, dragged: t(0))!
        list = PanelReorder.placing(t(0), in: list, at: first)
        let second = slot(pointer, in: list, dragged: t(0))!
        #expect(PanelReorder.placing(t(0), in: list, at: second) == list)
    }

    @Test func aTileFromAnotherSectionGoesInFrontOfTheOneUnderThePointer() {
        let list = tiles(5)
        let at = slot(centre(list, 3), in: list, dragged: t(9))!
        #expect(PanelReorder.placing(t(9), in: list, at: at) == [t(0), t(1), t(2), t(9), t(3), t(4)])
    }

    @Test func betweenRowsTheNearestRowWins() {
        let list = tiles(6)
        let frame = frames(list)
        // The 6pt gap between the rows, nearer the first row's bottom: the row
        // above, at the column of the pointer.
        let nearFirst = CGPoint(x: frame[t(1)]!.midX, y: frame[t(1)]!.maxY + 1)
        #expect(slot(nearFirst, in: list, dragged: t(9)) == 1)
        let nearSecond = CGPoint(x: frame[t(1)]!.midX, y: frame[t(4)]!.minY - 1)
        #expect(slot(nearSecond, in: list, dragged: t(9)) == 4)
        // Below the last row, in the zone's margin: still the last row's tile.
        let below = CGPoint(x: frame[t(5)]!.midX, y: frame[t(5)]!.maxY + 20)
        #expect(slot(below, in: list, dragged: t(9)) == 5)
    }

    @Test func pastTheLastTileOfARowItGoesAfterIt() {
        // 5 tiles in 3 columns: the second row has room after t4.
        let list = tiles(5)
        let frame = frames(list)[t(4)]!
        let room = CGPoint(x: frame.maxX + 20, y: frame.midY)
        #expect(slot(room, in: list, dragged: t(9)) == 5)
        // The same room, dragging t0: it ends last, not before t4.
        let moved = slot(room, in: list, dragged: t(0))!
        #expect(PanelReorder.placing(t(0), in: list, at: moved) == [t(1), t(2), t(3), t(4), t(0)])
        // Dragging the last tile itself: it is already there.
        let own = slot(room, in: list, dragged: t(4))!
        #expect(PanelReorder.placing(t(4), in: list, at: own) == list)
    }

    @Test func launchersAndTheFoldAreNotAimedAt() {
        let list = [t(0), t(1), .launcher("app.x"), .fold]
        // Over the launcher's cell, right of t1: after t1, the end of the icons.
        let over = centre(list, 2)
        #expect(slot(over, in: list, dragged: t(9)) == 2)
        #expect(PanelReorder.placing(t(9), in: list, at: 2) == [t(0), t(1), t(9), .launcher("app.x"), .fold])
        // Dragged t0 there: it ends last among the icons.
        let moved = slot(over, in: list, dragged: t(0))!
        #expect(PanelReorder.placing(t(0), in: list, at: moved) == [t(1), t(0), .launcher("app.x"), .fold])
    }

    @Test func nothingToAimAt() {
        #expect(PanelReorder.index(at: .zero, tiles: [], frames: [:], dragged: t(0)) == nil)
        #expect(PanelReorder.index(at: .zero, tiles: [.fold], frames: [:], dragged: t(0)) == nil)
    }

    @Test func aRowOfGroupsAimsAtTheNearestIcon() {
        // The row layout: icons in one line, a break between two groups.
        let list = [t(0), t(1), .rowBreak, t(2), t(3)]
        let grid = PanelGrid(tiles: list, columns: nil, layout: .row, showsNames: false)
        let frame = Dictionary(grid.rows.joined().map { ($0.tile, $0.frame) }, uniquingKeysWith: { first, _ in first })
        func at(_ tile: PanelTile) -> CGPoint { CGPoint(x: frame[tile]!.midX, y: frame[tile]!.midY) }
        // Over the first icon after the break: in front of it, in the second group.
        let there = PanelReorder.index(at: at(t(2)), tiles: list, frames: frame, dragged: t(9))!
        #expect(PanelReorder.placing(t(9), in: list, at: there) == [t(0), t(1), .rowBreak, t(9), t(2), t(3)])
        // Past the first group's last icon, in the divider's room: after it,
        // before the break.
        let gap = CGPoint(x: frame[t(1)]!.maxX + 3, y: frame[t(1)]!.midY)
        let end = PanelReorder.index(at: gap, tiles: list, frames: frame, dragged: t(9))!
        #expect(PanelReorder.placing(t(9), in: list, at: end) == [t(0), t(1), t(9), .rowBreak, t(2), t(3)])
    }

    // MARK: - Neighbour

    @Test func theNeighbourIsTheNextIcon() {
        let list = tiles(4)
        #expect(PanelReorder.neighbour(of: t(1), in: list) == PanelNeighbour(item: .bundleKey("t2"), afterBreak: false))
        #expect(PanelReorder.neighbour(of: t(3), in: list) == PanelNeighbour(item: nil, afterBreak: false))
        // Launchers and the fold are not neighbours on the bar.
        #expect(PanelReorder.neighbour(of: t(3), in: list + [.launcher("app.x"), .fold]).item == nil)
    }

    @Test func aBreakBetweenIsSaid() {
        let list = [t(0), .rowBreak, t(1), t(2)]
        #expect(PanelReorder.neighbour(of: t(0), in: list) == PanelNeighbour(item: .bundleKey("t1"), afterBreak: true))
        #expect(PanelReorder.neighbour(of: t(1), in: list) == PanelNeighbour(item: .bundleKey("t2"), afterBreak: false))
        // Last before a trailing break: no icon, but the break is said.
        #expect(PanelReorder.neighbour(of: t(0), in: [t(0), .rowBreak]) == PanelNeighbour(item: nil, afterBreak: true))
        // A tile that is not in the list has nothing beside it.
        #expect(PanelReorder.neighbour(of: t(9), in: list).item == nil)
    }

    // MARK: - The model

    private func model(hidden: [PanelTile], always: [PanelTile], over: [PanelTile] = []) -> PanelModel {
        var sections: [PanelSection] = []
        if !over.isEmpty { sections.append(PanelSection(kind: .didntFit, tiles: over, isFolded: false)) }
        sections.append(PanelSection(kind: .hidden, tiles: hidden, isFolded: false))
        sections.append(PanelSection(kind: .alwaysHidden, tiles: always, isFolded: false))
        return PanelModel(sections: sections, bestMatch: nil)
    }

    @Test func movingWithinASection() {
        let m = model(hidden: [t(0), t(1), t(2)], always: [t(5)])
        let out = m.moving(t(0), to: PanelSlot(kind: .hidden, index: 2))
        #expect(out.section(.hidden)?.tiles == [t(1), t(2), t(0)])
        #expect(out.section(.alwaysHidden)?.tiles == [t(5)])
    }

    @Test func movingToAnotherSectionLeavesTheOneItCameFrom() {
        let m = model(hidden: [t(0), t(1)], always: [t(5), t(6)])
        let out = m.moving(t(0), to: PanelSlot(kind: .alwaysHidden, index: 1))
        #expect(out.section(.hidden)?.tiles == [t(1)])
        #expect(out.section(.alwaysHidden)?.tiles == [t(5), t(0), t(6)])
    }

    @Test func keepingTheOriginHoldsItsSpace() {
        let m = model(hidden: [t(0), t(1)], always: [t(5), t(6)])
        let out = m.moving(t(0), to: PanelSlot(kind: .alwaysHidden, index: 0), keepingOrigin: true)
        #expect(out.section(.hidden)?.tiles == [t(0), t(1)])
        #expect(out.section(.alwaysHidden)?.tiles == [t(0), t(5), t(6)])
    }

    @Test func aSlotOnASectionTheModelLacksChangesNothing() {
        let m = PanelModel(sections: [PanelSection(kind: .hidden, tiles: [t(0)], isFolded: false)], bestMatch: nil)
        #expect(m.moving(t(0), to: PanelSlot(kind: .alwaysHidden, index: 0)) == m)
        #expect(!m.changes(t(0), at: PanelSlot(kind: .alwaysHidden, index: 0)))
    }

    @Test func aDropThatChangesNothingIsNoChange() {
        let m = model(hidden: [t(0), t(1), t(2)], always: [t(5)])
        // Its own place, from either side.
        #expect(!m.changes(t(1), at: PanelSlot(kind: .hidden, index: 1)))
        #expect(!m.changes(t(0), at: PanelSlot(kind: .hidden, index: 0)))
        #expect(!m.changes(t(2), at: PanelSlot(kind: .hidden, index: 2)))
        // Another place in the same section, or any place in another one.
        #expect(m.changes(t(1), at: PanelSlot(kind: .hidden, index: 0)))
        #expect(m.changes(t(1), at: PanelSlot(kind: .alwaysHidden, index: 0)))
    }

    @Test func aTileFromDidntFitIsAMoveToo() {
        let m = model(hidden: [t(0)], always: [], over: [t(7)])
        #expect(m.changes(t(7), at: PanelSlot(kind: .hidden, index: 0)))
        let out = m.moving(t(7), to: PanelSlot(kind: .hidden, index: 0))
        #expect(out.section(.hidden)?.tiles == [t(7), t(0)])
        #expect(out.section(.didntFit)?.tiles == [])
    }
}
