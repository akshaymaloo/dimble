import Testing
@testable import PelmetCore

@Suite struct OrderEditSettleTests {
    let a = ItemID.bundleKey("com.a"), b = ItemID.bundleKey("com.b"), c = ItemID.bundleKey("com.c")
    let quit = ItemID.bundleKey("com.quit")
    var roster: Roster { Roster(members: [a: .alwaysHidden, b: .alwaysHidden, c: .alwaysHidden, quit: .alwaysHidden]) }

    func settled(_ drawn: [ItemID], bar: [ItemID], onBar: Set<ItemID>, crossing: [ItemID] = []) -> Set<Section> {
        var edits = OrderEdits(order: [.alwaysHidden: drawn])
        for id in crossing { edits.previousSection[id] = .hidden }
        return OrderEditSettle.settledSections(edits, bar: bar, onBar: onBar, roster: roster)
    }

    @Test func aReorderInASectionNeverRevealedStaysPending() {
        // After launch Always Hidden is concealed and no frame remembers it:
        // every icon is on the bar, none can be placed.
        #expect(settled([b, a], bar: [], onBar: [a, b]).isEmpty)
    }

    @Test func aReorderWithOneIconUnseenStaysPending() {
        // a and b framed in the drawn order, c concealed with no frame.
        #expect(settled([a, b, c], bar: [a, b], onBar: [a, b, c]).isEmpty)
    }

    @Test func aDrawingTheBarMatchesInFullClears() {
        #expect(settled([a, b, c], bar: [a, b, c], onBar: [a, b, c]) == [.alwaysHidden])
    }

    @Test func aDrawingTheBarDisagreesWithStaysPending() {
        #expect(settled([b, a, c], bar: [a, b, c], onBar: [a, b, c]).isEmpty)
    }

    @Test func anIconNotOnTheBarAtAllIsNoEdit() {
        // Its app is not running: Apply drops it, so it keeps nothing pending.
        #expect(settled([a, quit, b], bar: [a, b], onBar: [a, b]) == [.alwaysHidden])
    }

    @Test func aDropBetweenSectionsWaitsForThePass() {
        #expect(settled([a, b], bar: [a, b], onBar: [a, b], crossing: [b]).isEmpty)
    }

    @Test func iconsOfOtherSectionsDoNotCount() {
        let visible = ItemID.bundleKey("com.visible")
        #expect(settled([a, b], bar: [a, visible, b], onBar: [a, b, visible]) == [.alwaysHidden])
    }
}
