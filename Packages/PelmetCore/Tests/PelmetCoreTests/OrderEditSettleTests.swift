import Testing
@testable import PelmetCore

@Suite struct OrderEditSettleTests {
    let a = ItemID.bundleKey("com.a"), b = ItemID.bundleKey("com.b"), c = ItemID.bundleKey("com.c")
    let quit = ItemID.bundleKey("com.quit")
    var roster: Roster { Roster(members: [a: .alwaysHidden, b: .alwaysHidden, c: .alwaysHidden, quit: .alwaysHidden]) }

    func settled(_ drawn: [ItemID], bar: [ItemID], onBar: Set<ItemID>, crossing: [ItemID] = []) -> Set<Section> {
        var edits = OrderEdits(order: [.alwaysHidden: drawn])
        for id in crossing { edits.previousSection[id] = .hidden }
        return OrderEditSettle.settledSections(edits, bar: bar, live: [], concealed: onBar, roster: roster)
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

    @Test func anOwnItemConcealedWithNoFrameIsNoEdit() {
        // A helper-hosted separator that drew once and let go: concealed,
        // never framed again.
        let separator = ItemID(rawValue: "status:\(PelmetBundle.alwaysHiddenHostID)::Pelmet.Separator.1")
        let members: [ItemID: Section] = [a: .alwaysHidden, b: .alwaysHidden, separator.sectionKey: .alwaysHidden]
        let edits = OrderEdits(order: [.alwaysHidden: [a, separator.sectionKey, b]])
        #expect(OrderEditSettle.settledSections(
            edits, bar: [a, b], live: [a, b], concealed: [separator], roster: Roster(members: members)
        ) == [.alwaysHidden])
        // Live, it counts like any icon: unframed, it keeps the edit.
        #expect(OrderEditSettle.settledSections(
            edits, bar: [a, b], live: [a, b, separator], concealed: [], roster: Roster(members: members)
        ).isEmpty)
        // Last seen behind the «, it is on the bar with no frame: pending.
        #expect(OrderEditSettle.settledSections(
            edits, bar: [a, b], live: [a, b], concealed: [separator],
            ownBehindOverflow: [separator.sectionKey], roster: Roster(members: members)
        ).isEmpty)
    }

    @Test func anOwnExtraConcealedWithItsSectionKeepsTheEditPending() {
        // Shortcuts reordered while Hidden is concealed: it hides by its own
        // visibility, so the walk has it neither live nor concealed, and no
        // frame places it. Live test, 2026-10-13: cleared at the drop.
        let shortcuts = ItemID(rawValue: "status:\(PelmetBundle.mainID)::Pelmet.Shortcuts")
        let members: [ItemID: Section] = [a: .hidden, b: .hidden, shortcuts: .hidden]
        let edits = OrderEdits(order: [.hidden: [a, shortcuts, b]])
        #expect(OrderEditSettle.settledSections(
            edits, bar: [a, b], live: [], concealed: [a, b], ownExtras: [shortcuts], roster: Roster(members: members)
        ).isEmpty)
        // Framed again (Hidden revealed) in the drawn order, it settles.
        #expect(OrderEditSettle.settledSections(
            edits, bar: [a, shortcuts, b], live: [a, shortcuts, b], concealed: [],
            ownExtras: [shortcuts], roster: Roster(members: members)
        ) == [.hidden])
        // An idle extra (camera off) is still no edit.
        #expect(OrderEditSettle.settledSections(
            edits, bar: [a, b], live: [], concealed: [a, b], roster: Roster(members: members)
        ) == [.hidden])
    }

    @Test func anOwnExtraDroppedBetweenSectionsWaitsForThePassEvenUnseen() {
        let shortcuts = ItemID(rawValue: "status:\(PelmetBundle.mainID)::Pelmet.Shortcuts")
        let members: [ItemID: Section] = [a: .hidden, b: .hidden, shortcuts: .hidden]
        var edits = OrderEdits(order: [.hidden: [a, b, shortcuts]])
        edits.previousSection[shortcuts] = .visible
        #expect(OrderEditSettle.settledSections(
            edits, bar: [a, b, shortcuts], live: [a, b], concealed: [], ownExtras: [shortcuts], roster: Roster(members: members)
        ).isEmpty)
    }

    @Test func iconsOfOtherSectionsDoNotCount() {
        let visible = ItemID.bundleKey("com.visible")
        #expect(settled([a, b], bar: [a, visible, b], onBar: [a, b, visible]) == [.alwaysHidden])
    }
}
