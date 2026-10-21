import Foundation
import Testing
@testable import PelmetCore

@Suite struct OrderFromBarTests {
    private func key(_ name: String) -> ItemID {
        ItemID(rawValue: "bundle:\(name)")
    }

    private func model(_ hidden: [String], _ alwaysHidden: [String] = [], new: [String] = []) -> SectionModel {
        var assignments: [ItemID: Section] = [:]
        for name in hidden + new { assignments[key(name)] = .hidden }
        for name in alwaysHidden { assignments[key(name)] = .alwaysHidden }
        return SectionModel(
            assignments: assignments,
            order: [.hidden: hidden.map(key), .alwaysHidden: alwaysHidden.map(key)]
        )
    }

    @Test func newIconTakesTheSlotAfterItsLeftNeighbour() {
        var m = model(["a", "b", "c"], new: ["n"])
        let slotted = m.slotUnlisted(bar: ["a", "b", "n", "c"].map(key))
        #expect(slotted == [key("n")])
        #expect(m.order[.hidden] == ["a", "b", "n", "c"].map(key))
    }

    @Test func leftEndOfItsSectionGoesBeforeItsRightNeighbour() {
        // Left of it sits Always Hidden: no listed Hidden neighbour there.
        var m = model(["a", "b"], ["x"], new: ["n"])
        m.slotUnlisted(bar: ["x", "n", "a", "b"].map(key))
        #expect(m.order[.hidden] == ["n", "a", "b"].map(key))
        #expect(m.order[.alwaysHidden] == [key("x")])
    }

    @Test func aSectionWithNoListedIconListsItLast() {
        var m = model([], new: ["n"])
        m.order = [:]
        m.slotUnlisted(bar: [key("n")])
        #expect(m.order[.hidden] == [key("n")])
    }

    @Test func iconsThatArrivedTogetherKeepTheirOrder() {
        var m = model(["a", "b"], new: ["n", "o"])
        m.slotUnlisted(bar: ["a", "n", "o", "b"].map(key))
        #expect(m.order[.hidden] == ["a", "n", "o", "b"].map(key))
    }

    @Test func listedAndExemptIconsStayPut() {
        var m = model(["a", "b"], new: ["n"])
        let slotted = m.slotUnlisted(bar: ["b", "n", "a"].map(key), exempt: [key("n")])
        #expect(slotted.isEmpty)
        #expect(m.order[.hidden] == ["a", "b"].map(key))
    }

    @Test func aStaleEntryInAnotherSectionGoes() {
        var m = model(["a"], ["x"], new: ["n"])
        m.order[.alwaysHidden] = ["x", "n"].map(key)
        m.slotUnlisted(bar: ["x", "a", "n"].map(key))
        #expect(m.order[.hidden] == ["a", "n"].map(key))
        #expect(m.order[.alwaysHidden] == [key("x")])
    }

    @Test func visibleNewcomerSlotsAmongVisible() {
        // Unassigned is Visible: it lists between its Visible neighbours.
        var m = SectionModel(order: [.visible: ["v", "w"].map(key)])
        m.slotUnlisted(bar: ["v", "n", "w"].map(key))
        #expect(m.order[.visible] == ["v", "n", "w"].map(key))
    }

    @Test func neighboursAcrossTheChevronAreNoSlot() {
        // "s", Visible, sits left of the « (a stray): "n" lists before "w",
        // its neighbour on its own side, not after "s".
        var m = SectionModel(assignments: [key("h"): .hidden], order: [.visible: ["w", "s"].map(key), .hidden: [key("h")]])
        m.slotUnlisted(bar: ["h", "s", "chev", "n", "w"].map(key), chevron: key("chev"))
        #expect(m.order[.visible] == ["n", "w", "s"].map(key))
        #expect(m.order[.hidden] == [key("h")])
    }

    @Test func foldTakesTheBarsOrderAmongTheSeenSlots() {
        // "u" isn't on the bar (concealed, never framed): it keeps its slot.
        var m = model(["a", "u", "b", "c"])
        let changed = m.foldBarOrder(of: .hidden, bar: ["c", "a", "b"].map(key))
        #expect(changed)
        #expect(m.order[.hidden] == ["c", "u", "a", "b"].map(key))
    }

    @Test func foldOfABarAlreadyInOrderChangesNothing() {
        var m = model(["a", "b"], ["x"])
        let hidden = m.foldBarOrder(of: .hidden, bar: ["x", "a", "b"].map(key))
        let visible = m.foldBarOrder(of: .visible, bar: [key("a")])
        #expect(!hidden && !visible)
    }

    @Test func foldLeavesAnEntryOfAnotherSection() {
        // A stale "x" in Hidden's list is not Hidden's to sort.
        var m = model(["a", "b"], ["x"])
        m.order[.hidden] = ["a", "x", "b"].map(key)
        m.foldBarOrder(of: .hidden, bar: ["x", "b", "a"].map(key))
        #expect(m.order[.hidden] == ["b", "x", "a"].map(key))
    }
}
