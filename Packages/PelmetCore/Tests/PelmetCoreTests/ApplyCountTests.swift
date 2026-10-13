import Testing
@testable import PelmetCore

@Suite struct ApplyCountTests {
    let chevron = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.StatusItem")
    let sound = ItemID(rawValue: "status:com.apple.MenuBarAgent::com.apple.menuextra.sound")
    let shortcuts = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.Shortcuts")
    let a = ItemID.bundleKey("com.a"), b = ItemID.bundleKey("com.b"), c = ItemID.bundleKey("com.c")
    let v1 = ItemID.bundleKey("com.v1")

    var roster: Roster {
        Roster(members: [a: .hidden, b: .hidden, c: .hidden, sound: .hidden, shortcuts: .hidden])
    }

    func isConcealed(
        _ id: ItemID, drawn: Set<ItemID> = [], concealedKeys: Set<ItemID> = [], idle: Set<ItemID> = [],
        sections: [ItemID: Section] = [:], revealed: Set<Section> = []
    ) -> Bool {
        ApplyCount.isConcealed(
            id, drawn: drawn.contains, concealedKeys: concealedKeys,
            wouldShow: { !idle.contains($0) }, section: { sections[$0] ?? .visible }, revealed: revealed
        )
    }

    @Test func aConcealedDropCountsOnceAndItsAnchorNever() {
        // Shortcuts (an own extra) dropped after Sound in a concealed Hidden.
        // Just after the conceal the walk lists both, leftovers on top of
        // each other, so neither is on the collapsed bar and both read as
        // behind the «: "Apply (2)" for one move (live test, 2026-10-13).
        let edits = OrderEdits(order: [.hidden: [a, sound, shortcuts]], dropped: [shortcuts])
        let concealed: (ItemID) -> Bool = {
            isConcealed($0, concealedKeys: [sound], sections: [sound: .hidden, shortcuts: .hidden])
        }
        let collapsed = MovePlan.compute(bar: [a, chevron, v1], edits: edits, roster: roster, chevron: chevron)
        let count = ApplyCount.count(
            collapsed, edits: edits, trapped: [sound, shortcuts], drawn: { _ in false }, concealed: concealed
        )
        #expect(count == ApplyCount.Count(trapped: [], concealed: [shortcuts], total: 1))
        // Revealed, the same edit is the one move it always was.
        let revealed = MovePlan.compute(
            bar: [a, shortcuts, sound, chevron, v1], edits: edits, roster: roster, chevron: chevron
        )
        #expect(revealed.moves == [Move(item: shortcuts, after: sound, before: chevron)])
        let shown = ApplyCount.count(revealed, edits: edits, trapped: [], drawn: { _ in true }, concealed: { _ in false })
        #expect(shown.total == 1)
    }

    @Test func aConcealedDropReadsOneEvenWhereAStaleFrameSaysItIsInPlace() {
        // Sound's remembered frame is from before Snib's drag moved it, so
        // the collapsed bar reads Sound after Snib already and the plan finds
        // nothing. Sound dropped after Snib in a concealed Hidden read a
        // plain "Apply", and the pass then found the move (live test,
        // 2026-10-13).
        let snib = ItemID.bundleKey("app.fif7y.Snib")
        let roster = Roster(members: [a: .hidden, snib: .hidden, sound: .hidden])
        let edits = OrderEdits(
            order: [.hidden: [a, snib, sound]], previousOrder: [.hidden: [a, sound, snib]], dropped: [sound]
        )
        let concealed: (ItemID) -> Bool = {
            isConcealed($0, concealedKeys: Set([a, snib, sound].map(\.sectionKey)), sections: [sound: .hidden])
        }
        let stale = MovePlan.compute(bar: [a, snib, sound, chevron, v1], edits: edits, roster: roster, chevron: chevron)
        #expect(stale.moves.isEmpty)
        #expect(ApplyCount.count(stale, edits: edits, trapped: [], drawn: { _ in false }, concealed: concealed).total == 1)
        // A frame that sees it out of place: the one move, not two.
        let seen = MovePlan.compute(bar: [a, sound, snib, chevron, v1], edits: edits, roster: roster, chevron: chevron)
        #expect(seen.moves.map(\.item) == [sound])
        #expect(ApplyCount.count(seen, edits: edits, trapped: [], drawn: { _ in false }, concealed: concealed)
            == ApplyCount.Count(trapped: [], concealed: [], total: 1))
        // A drop no drawing lists any more raises nothing.
        let leftover = OrderEdits(dropped: [sound])
        let none = MovePlan.compute(bar: [a, snib, sound, chevron, v1], edits: leftover, roster: roster, chevron: chevron)
        #expect(ApplyCount.count(none, edits: leftover, trapped: [], drawn: { _ in false }, concealed: concealed).total == 0)
    }

    @Test func aRealMoveAndAnOutAndBackInOneConcealedSectionReadOne() {
        // Sound dropped to a new slot in a concealed Hidden, then Snib
        // dragged out and back: both dropped, one move. Counted per
        // concealed drop it read "Apply (2)", and 1 once revealed (review,
        // 2026-10-13).
        let snib = ItemID.bundleKey("app.fif7y.Snib")
        let roster = Roster(members: [a: .hidden, snib: .hidden, sound: .hidden])
        let edits = OrderEdits(
            order: [.hidden: [a, snib, sound]], previousOrder: [.hidden: [a, sound, snib]], dropped: [sound, snib]
        )
        let concealed: (ItemID) -> Bool = {
            isConcealed($0, concealedKeys: Set([a, snib, sound].map(\.sectionKey)), sections: [sound: .hidden])
        }
        let collapsed = MovePlan.compute(bar: [a, sound, snib, chevron, v1], edits: edits, roster: roster, chevron: chevron)
        #expect(ApplyCount.count(collapsed, edits: edits, trapped: [], drawn: { _ in false }, concealed: concealed).total == 1)
        let revealed = MovePlan.compute(bar: [a, sound, snib, chevron, v1], edits: edits, roster: roster, chevron: chevron)
        #expect(ApplyCount.count(revealed, edits: edits, trapped: [], drawn: { _ in true }, concealed: { _ in false }).total == 1)
        // The same with two third-party icons, a then b.
        let ab = OrderEdits(order: [.hidden: [b, a, c]], previousOrder: [.hidden: [a, b, c]], dropped: [a, b])
        let hiddenABC: (ItemID) -> Bool = { isConcealed($0, concealedKeys: [a, b, c]) }
        let abPlan = MovePlan.compute(bar: [a, b, c, chevron, v1], edits: ab, roster: self.roster, chevron: chevron)
        #expect(ApplyCount.count(abPlan, edits: ab, trapped: [], drawn: { _ in false }, concealed: hiddenABC).total == 1)
    }

    @Test func aTrappedDropCountsAndATrappedNeighbourDoesNot() {
        // b dropped after c, both behind the «: the pass expands it for b,
        // and c is only where b lands.
        let edits = OrderEdits(order: [.hidden: [a, c, b]], dropped: [b])
        let plan = MovePlan.compute(bar: [a, chevron, v1], edits: edits, roster: roster, chevron: chevron)
        let count = ApplyCount.count(plan, edits: edits, trapped: [b, c], drawn: { _ in true }, concealed: { _ in false })
        #expect(count == ApplyCount.Count(trapped: [b], concealed: [], total: 1))
    }

    @Test func aDropBesideADrawnTrappedNeighbourStillCountsOne() {
        // Hidden revealed, the bar [a, b, c, v1] with c behind the «, and b
        // dropped after c. Without c the plan finds nothing to do, and c was
        // not dropped, yet the pass expands the « for c and drags b
        // (review, 2026-10-13).
        let edits = OrderEdits(order: [.hidden: [a, c, b]], dropped: [b])
        let plan = MovePlan.compute(bar: [a, b, chevron, v1], edits: edits, roster: roster, chevron: chevron)
        #expect(plan.moves.isEmpty)
        let count = ApplyCount.count(plan, edits: edits, trapped: [c], drawn: { _ in true }, concealed: { _ in false })
        #expect(count == ApplyCount.Count(trapped: [], concealed: [], total: 1))
        // A leftover the bar no longer draws is not behind the «: no floor.
        let leftover = ApplyCount.count(plan, edits: edits, trapped: [c], drawn: { _ in false }, concealed: { _ in false })
        #expect(leftover.total == 0)
    }

    @Test func drawnWinsOverTheConcealedSet() {
        // An icon out on its own, or one macOS will not hide, stays on the bar.
        #expect(!isConcealed(b, drawn: [b], concealedKeys: [b], sections: [b: .hidden]))
        #expect(isConcealed(b, concealedKeys: [b], sections: [b: .hidden]))
    }

    @Test func theConcealedSetIsReadByCanonicalKey() {
        let item = ItemID(rawValue: "status:com.b::Item-0")
        #expect(isConcealed(item, concealedKeys: [item.sectionKey]))
    }

    @Test func anOwnExtraIsConcealedWithItsSectionOnlyWhileItWouldShow() {
        let sections: [ItemID: Section] = [shortcuts: .hidden]
        #expect(isConcealed(shortcuts, sections: sections))
        #expect(!isConcealed(shortcuts, idle: [shortcuts], sections: sections))
        #expect(!isConcealed(shortcuts, sections: sections, revealed: [.hidden]))
        #expect(!isConcealed(shortcuts, sections: [shortcuts: .visible]))
    }

    @Test func anIconOutsideTheSetIsNotConcealed() {
        // Undrawn and unlisted (a leftover, a third-party icon behind the «):
        // only an own extra is concealed by its section alone.
        #expect(!isConcealed(b, sections: [b: .hidden]))
        #expect(!isConcealed(chevron, sections: [chevron: .hidden]))
    }
}
