import CoreGraphics
import Foundation
import Testing
@testable import PelmetCore

@Suite struct PanelGridTests {
    private func tiles(_ n: Int) -> [PanelTile] {
        (0..<n).map { .item(.bundleKey("t\($0)")) }
    }

    private func t(_ i: Int) -> PanelTile { .item(.bundleKey("t\(i)")) }

    private func grid(
        _ tiles: [PanelTile], columns: Int? = nil, layout: PanelGrid.Layout = .panel,
        names: Bool = false, minimumColumns: Int = 1
    ) -> PanelGrid {
        PanelGrid(tiles: tiles, columns: columns, layout: layout, showsNames: names, minimumColumns: minimumColumns)
    }

    private func counts(_ grid: PanelGrid) -> [Int] { grid.rows.map(\.count) }

    // MARK: - Metrics

    // The numbers come from the design mock's cfg(); a change here is a design change.
    @Test func metricsAreTheMocks() {
        #expect(PanelMetrics.standard(layout: .panel, showsNames: false) == .compact)
        #expect(PanelMetrics.standard(layout: .panel, showsNames: true) == .named)
        #expect(PanelMetrics.standard(layout: .row, showsNames: true) == .row)
        #expect(PanelMetrics.compact.tileSize == CGSize(width: 44, height: 44))
        #expect(PanelMetrics.compact.columnGap == 6 && PanelMetrics.compact.rowGap == 6)
        #expect(PanelMetrics.named.tileSize == CGSize(width: 68, height: 63))
        #expect(PanelMetrics.named.columnGap == 2 && PanelMetrics.named.rowGap == 8)
        #expect(PanelMetrics.named.labelHeight == 13 && PanelMetrics.named.labelGap == 5)
        #expect(PanelMetrics.row.tileSize == CGSize(width: 34, height: 28))
        #expect(PanelMetrics.compact.padding == 10 && PanelMetrics.row.padding == 5)
    }

    // MARK: - Columns

    @Test func autoIsFiveColumnsAndWraps() {
        let g = grid(tiles(7))
        #expect(g.columnCount == 5)
        #expect(counts(g) == [5, 2])
        #expect(g.rows[1][1].tile == t(6))
        #expect(g.rows[1][1].row == 1 && g.rows[1][1].column == 1)
    }

    // No wider than the icons need, so three icons are three columns.
    @Test func theGridShrinksToItsIcons() {
        #expect(grid(tiles(3)).columnCount == 3)
        #expect(grid(tiles(1), columns: 8).columnCount == 1)
    }

    @Test func aSettingIsTheMostNotTheExact() {
        #expect(counts(grid(tiles(7), columns: 3)) == [3, 3, 1])
        #expect(grid(tiles(3), columns: 8).columnCount == 3)
        #expect(grid(tiles(4), columns: 0).columnCount == 1)
        #expect(grid(tiles(12), columns: 10).columnCount == 10)
    }

    // Stacked sections share the widest one's width, never past the setting.
    @Test func minimumColumnsLetSectionsShareAWidth() {
        #expect(grid(tiles(2), minimumColumns: 4).columnCount == 4)
        #expect(grid(tiles(2), columns: 3, minimumColumns: 4).columnCount == 3)
        let wide = PanelGrid.neededColumns(of: tiles(9), maximum: nil)
        #expect(wide == 5)
        #expect(PanelGrid.neededColumns(of: tiles(2), maximum: nil) == 2)
    }

    // MARK: - Frames and size

    @Test func compactFramesAndSize() {
        let g = grid(tiles(7))
        #expect(g.rows[0][0].frame == CGRect(x: 0, y: 0, width: 44, height: 44))
        #expect(g.rows[0][4].frame == CGRect(x: 200, y: 0, width: 44, height: 44))
        #expect(g.rows[1][1].frame == CGRect(x: 50, y: 50, width: 44, height: 44))
        #expect(g.contentSize == CGSize(width: 244, height: 94))
        #expect(g.panelSize == CGSize(width: 264, height: 114))
    }

    @Test func namedFramesAndSize() {
        let g = grid(tiles(7), names: true)
        #expect(g.showsNames)
        #expect(g.rows[1][1].frame == CGRect(x: 70, y: 71, width: 68, height: 63))
        #expect(g.contentSize == CGSize(width: 348, height: 134))
    }

    // The fold's label set a 150pt floor; with it gone the grid is its icons.
    @Test func aNarrowPanelIsAsWideAsItsIcons() {
        let g = grid(tiles(3))
        #expect(g.contentSize == CGSize(width: 144, height: 44))
        #expect(g.rows[0][2].frame.maxX == 144)
    }

    @Test func noTilesNoSize() {
        let g = grid([])
        #expect(g.rows.isEmpty && g.columnCount == 0)
        #expect(g.contentSize == .zero && g.panelSize == .zero)
        #expect(g.firstTile == nil)
        #expect(grid([.rowBreak, .rowBreak]).rows.isEmpty)
    }

    // MARK: - Row breaks

    @Test func aBreakStartsANewRowWithAGroupGap() {
        let g = grid([t(0), t(1), .rowBreak, t(2), t(3), t(4)])
        #expect(counts(g) == [2, 3])
        #expect(g.columnCount == 3)
        // A tile and its row gap (50), then the separator's own 4pt between two row gaps (10).
        #expect(g.rows[1][0].frame.minY == 60)
        #expect(g.contentSize.height == 104)
    }

    // A wrapped row inside one group is only a row gap apart.
    @Test func wrappingInsideAGroupAddsNoGroupGap() {
        let g = grid(tiles(6), columns: 3)
        #expect(g.rows[1][0].frame.minY == 50)
    }

    @Test func breaksNeverMakeEmptyRows() {
        let g = grid([.rowBreak, t(0), .rowBreak, .rowBreak, t(1), .rowBreak])
        #expect(counts(g) == [1, 1])
        #expect(g.rows.allSatisfy { !$0.isEmpty })
        #expect(g.placement(of: .rowBreak) == nil)
    }

    @Test func eachGroupWrapsOnItsOwn() {
        let g = grid([t(0), t(1), t(2), t(3), .rowBreak, t(4)], columns: 3)
        #expect(counts(g) == [3, 1, 1])
        // Wrapped once (50), a row (44 + 6), then the group gap (4 + 6).
        #expect(g.rows[2][0].frame.minY == 110)
    }

    // MARK: - Row layout

    @Test func rowIsOneRowWithNoNames() {
        let g = grid(tiles(8), columns: 2, layout: .row, names: true)
        #expect(counts(g) == [8])
        #expect(g.columnCount == 8)
        #expect(!g.showsNames)
        #expect(g.metrics == .row)
        #expect(g.rows[0][3].frame == CGRect(x: 102, y: 0, width: 34, height: 28))
        #expect(g.contentSize == CGSize(width: 272, height: 28))
        #expect(g.panelSize == CGSize(width: 282, height: 38))
    }

    @Test func breaksAreDividersInARow() {
        let g = grid([.rowBreak, t(0), t(1), .rowBreak, .rowBreak, t(2), .rowBreak], layout: .row)
        #expect(counts(g) == [3])
        #expect(g.dividers == [CGRect(x: 68, y: 0, width: 13, height: 28)])
        #expect(g.rows[0][2].frame.minX == 81)
        #expect(g.contentSize.width == 115)
    }

    @Test func panelLayoutHasNoDividers() {
        #expect(grid([t(0), .rowBreak, t(1)]).dividers.isEmpty)
    }

    private func row(_ tiles: [PanelTile], maxWidth: CGFloat) -> PanelGrid {
        PanelGrid(tiles: tiles, columns: nil, layout: .row, showsNames: false, maxWidth: maxWidth)
    }

    // A row that fits stays one row, whatever the room.
    @Test func aRowThatFitsNeverWraps() {
        let g = row(tiles(8), maxWidth: 1000)
        #expect(counts(g) == [8])
        #expect(g.contentSize == CGSize(width: 272, height: 28))
    }

    // Too wide for the display: two even rows, not a full one over a stub.
    @Test func aRowTooWideWrapsIntoEvenRows() {
        let g = row(tiles(10), maxWidth: 200)
        #expect(counts(g) == [5, 5])
        #expect(g.columnCount == 5)
        #expect(g.rows[1][0].frame == CGRect(x: 0, y: 30, width: 34, height: 28))
        #expect(g.contentSize == CGSize(width: 170, height: 58))
        #expect(g.neighbour(of: t(1), toward: .down) == t(6))
        #expect(g.neighbour(of: t(4), toward: .right) == t(5))
        // Three fit at 110: the spare tiles go to the first rows.
        #expect(counts(row(tiles(7), maxWidth: 110)) == [3, 2, 2])
        #expect(counts(row(tiles(10), maxWidth: 120)) == [3, 3, 2, 2])
    }

    // A divider stays inside a row; at a wrap the new row is the separation.
    @Test func aWrapDropsTheDividerItLandsOn() {
        let kept = row([t(0), .rowBreak, t(1), t(2), t(3)], maxWidth: 100)
        #expect(counts(kept) == [2, 2])
        #expect(kept.dividers == [CGRect(x: 34, y: 0, width: 13, height: 28)])
        #expect(kept.contentSize.width == 81)
        let dropped = row([t(0), t(1), t(2), .rowBreak, t(3), t(4), t(5)], maxWidth: 150)
        #expect(counts(dropped) == [3, 3])
        #expect(dropped.dividers.isEmpty)
    }

    // MARK: - Row tiles follow their pictures (#102)

    private func wideRow(
        _ tiles: [PanelTile], pictures: [PanelTile: CGFloat], maxWidth: CGFloat? = nil
    ) -> PanelGrid {
        PanelGrid(tiles: tiles, columns: nil, layout: .row, showsNames: false, maxWidth: maxWidth,
                  pictureWidths: pictures)
    }

    // The picture's width and the 6pt the 34/28 well leaves round its room;
    // never under today's 34, never over twice it.
    @Test func aRowTileIsItsPicturePlusTheMarginWithinThePanelsBounds() {
        let metrics = PanelMetrics.row
        #expect(metrics.rowTileWidth(forPicture: 55) == 61)
        #expect(metrics.rowTileWidth(forPicture: 100) == 68)
        #expect(metrics.rowTileWidth(forPicture: nil) == 34)
        #expect(metrics.rowTileWidth(forPicture: 20) == 34)
        #expect(metrics.rowTileWidth(forPicture: 28) == 34)
        #expect(metrics.rowTileWidth(forPicture: 62) == 68)
        // Whole points, rounded up, so the picture's room is never short.
        #expect(metrics.rowTileWidth(forPicture: 55.2) == 62)
        #expect(metrics.rowTileWidth(forPicture: .nan) == 34)
        #expect(metrics.rowTileWidth(forPicture: 0) == 34)
    }

    @Test func aRowPlacesEachTileAtItsOwnWidth() {
        // A battery with its percentage, a text item that would run away, an
        // app icon's stand-in (no picture), and a small glyph.
        let g = wideRow([t(0), t(1), t(2), t(3), t(4)], pictures: [t(1): 55, t(2): 100, t(4): 16])
        #expect(g.rows[0].map(\.frame.minX) == [0, 34, 95, 163, 197])
        #expect(g.rows[0].map(\.frame.width) == [34, 61, 68, 34, 34])
        #expect(g.rows[0].allSatisfy { $0.frame.height == 28 })
        // The capsule is as wide as the tiles it holds, 231.
        #expect(g.contentSize == CGSize(width: 231, height: 28))
        #expect(g.panelSize == CGSize(width: 241, height: 38))
        #expect(g.tileWidth(of: t(1)) == 61 && g.tileWidth(of: t(2)) == 68 && g.tileWidth(of: t(0)) == 34)
        // The well fills the tile in the row, and is the metrics' elsewhere.
        #expect(g.wellSize(tileWidth: 61) == CGSize(width: 61, height: 28))
        #expect(grid(tiles(2)).wellSize(tileWidth: 61) == PanelMetrics.compact.wellSize)
    }

    // Tiles with no entry are the standard 34, so a row of stand-ins is what it was.
    @Test func aRowWithoutPicturesIsAsItWas() {
        let plain = grid(tiles(8), layout: .row)
        #expect(wideRow(tiles(8), pictures: [:]) == plain)
        #expect(plain.contentSize == CGSize(width: 272, height: 28))
    }

    @Test func dividersAndTheNextTileFollowAWideTile() {
        let g = wideRow([t(0), .rowBreak, t(1), t(2)], pictures: [t(0): 55, t(1): 100])
        // 61, the divider's 13, then 68 and 34.
        #expect(g.dividers == [CGRect(x: 61, y: 0, width: 13, height: 28)])
        #expect(g.rows[0].map(\.frame.minX) == [0, 74, 142])
        #expect(g.contentSize.width == 176)
    }

    @Test func thePanelLayoutIgnoresPictureWidths() {
        let seven = tiles(7)
        let wide = PanelGrid(tiles: seven, columns: 3, layout: .panel, showsNames: true,
                             pictureWidths: [t(0): 100, t(1): 55])
        #expect(wide == grid(seven, columns: 3, names: true))
        #expect(wide.tileWidth(of: t(0)) == 68)
        #expect(wide.wellSize(tileWidth: 61) == PanelMetrics.named.wellSize)
    }

    // The wrap counts widths, not tiles: 61 + 61 fit 130, a third does not.
    @Test func aRowWrapsByTheWidthsItHolds() {
        let g = wideRow([t(0), t(1), t(2), t(3)], pictures: [t(0): 55, t(1): 55], maxWidth: 130)
        #expect(counts(g) == [2, 2])
        #expect(g.rows[1][0].frame == CGRect(x: 0, y: 30, width: 34, height: 28))
        #expect(g.contentSize == CGSize(width: 122, height: 58))
        // Only ever one row where all of it fits.
        #expect(counts(wideRow([t(0), t(1), t(2), t(3)], pictures: [t(0): 55, t(1): 55], maxWidth: 190)) == [4])
    }

    // Two 68s and four 34s in 140: the first row can't take its share of
    // three, and the rest then takes four rather than leaving a stub.
    @Test func aRowThatBreaksEarlyForWidthLeavesNoStub() {
        let g = wideRow(tiles(6), pictures: [t(0): 100, t(1): 100], maxWidth: 140)
        #expect(counts(g) == [2, 4])
        #expect(g.rows.allSatisfy { $0.last!.frame.maxX <= 140 })
        #expect(g.contentSize == CGSize(width: 136, height: 58))
    }

    // A tile wider than the display's room still gets a row of its own.
    @Test func aTileWiderThanTheRoomStandsAlone() {
        let g = wideRow(tiles(3), pictures: [t(0): 100], maxWidth: 50)
        #expect(counts(g) == [1, 1, 1])
    }

    // MARK: - Arrow keys

    // Up and down land on the tile nearest across when the widths differ.
    @Test func upAndDownInAWideRowLandOnTheNearestTile() {
        // Row 0: 68, 68 (x 0..136); row 1: 34s at 0, 34, 68, 102.
        let g = wideRow(tiles(6), pictures: [t(0): 100, t(1): 100], maxWidth: 140)
        #expect(counts(g) == [2, 4])
        // t0's middle is 34: t2 (17) and t3 (51) are as near; the first wins.
        #expect(g.neighbour(of: t(0), toward: .down) == t(2))
        // t1's middle is 102: t5 (119) and t4 (85) are 17 either side.
        #expect(g.neighbour(of: t(1), toward: .down) == t(4))
        #expect(g.neighbour(of: t(5), toward: .up) == t(1))
        #expect(g.neighbour(of: t(2), toward: .up) == t(0))
        #expect(g.neighbour(of: t(3), toward: .up) == t(0))
        #expect(g.neighbour(of: t(4), toward: .up) == t(1))
    }

    @Test func rightAndLeftWalkTheRowsAndStopAtTheEnds() {
        let g = grid(tiles(7))
        #expect(g.neighbour(of: t(0), toward: .right) == t(1))
        #expect(g.neighbour(of: t(4), toward: .right) == t(5))
        #expect(g.neighbour(of: t(6), toward: .right) == nil)
        #expect(g.neighbour(of: t(5), toward: .left) == t(4))
        #expect(g.neighbour(of: t(0), toward: .left) == nil)
    }

    @Test func upAndDownKeepTheColumnAndClampToAShortRow() {
        let g = grid(tiles(7))
        #expect(g.neighbour(of: t(1), toward: .down) == t(6))
        #expect(g.neighbour(of: t(3), toward: .down) == t(6))
        #expect(g.neighbour(of: t(6), toward: .up) == t(1))
        #expect(g.neighbour(of: t(2), toward: .up) == nil)
        #expect(g.neighbour(of: t(6), toward: .down) == nil)
    }

    // Groups are rows to the keyboard.
    @Test func arrowsCrossARowBreak() {
        let g = grid([t(0), t(1), .rowBreak, t(2), t(3), t(4)])
        #expect(g.neighbour(of: t(1), toward: .right) == t(2))
        #expect(g.neighbour(of: t(1), toward: .down) == t(3))
    }

    @Test func aRowOnlyGoesAlongAndAnUnknownTileGoesNowhere() {
        let g = grid(tiles(3), layout: .row)
        #expect(g.neighbour(of: t(0), toward: .right) == t(1))
        #expect(g.neighbour(of: t(2), toward: .right) == nil)
        #expect(g.neighbour(of: t(1), toward: .up) == nil)
        #expect(g.neighbour(of: t(1), toward: .down) == nil)
        #expect(g.neighbour(of: t(9), toward: .left) == nil)
        #expect(g.firstTile == t(0))
    }
}
