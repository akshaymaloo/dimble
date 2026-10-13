import CoreGraphics
import Testing
@testable import PelmetCore

@Suite struct FrameMemoryTests {
    let chevron = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.StatusItem")
    let sound = ItemID(rawValue: "status:com.apple.MenuBarAgent::com.apple.menuextra.sound")
    let snib = ItemID.bundleKey("app.fif7y.Snib")
    let a = ItemID.bundleKey("com.a"), v1 = ItemID.bundleKey("com.v1")
    var roster: Roster { Roster(members: [a: .hidden, snib: .hidden, sound: .hidden]) }
    var hidden: Set<ItemID> { [a, snib, sound] }

    func frame(_ x: CGFloat) -> CGRect { CGRect(x: x, y: 0, width: 20, height: 24) }
    var live: [ItemID: CGRect] { [chevron: frame(200), v1: frame(230)] }

    /// The collapsed bar as the count and the settle read it: live frames,
    /// plus the remembered frame of each concealed icon.
    func bar(_ memory: FrameMemory) -> [ItemID] {
        let concealed = memory.frames.filter { hidden.contains($0.key) }
        return live.merging(concealed) { now, _ in now }.sorted { $0.value.minX < $1.value.minX }.map(\.key)
    }

    func count(_ edits: OrderEdits, bar: [ItemID]) -> Int {
        let plan = MovePlan.compute(bar: bar, edits: edits, roster: roster, chevron: chevron)
        return ApplyCount.count(
            plan, edits: edits, trapped: [], drawn: { _ in false }, concealed: { hidden.contains($0) }
        ).total
    }

    @Test func aRealReorderAfterAPassStaysPendingAndCounts() {
        // Hidden last read at rest as a, Snib, Sound. A pass then dragged
        // Snib while Hidden stayed concealed, so the bar is a, Sound, Snib
        // and nothing re-read it. Sound dropped after Snib is a real move.
        var memory = FrameMemory()
        memory.remember(
            [a: frame(100), snib: frame(130), sound: frame(160)].merging(live) { $1 },
            chevronMidX: 210, atRest: true
        )
        let edits = OrderEdits(
            order: [.hidden: [a, snib, sound]], previousOrder: [.hidden: [a, sound, snib]], dropped: [sound]
        )
        // Kept, the stale frames match the drawing in full: the settle
        // cleared the real edit at the drop, and Apply went dark (review,
        // 2026-10-13).
        #expect(OrderEditSettle.settledSections(
            edits, bar: bar(memory), live: Set(live.keys), concealed: hidden, roster: roster
        ) == [.hidden])
        // The walk after the drags reads Visible only: Hidden's frames go.
        #expect(memory.forget(allBut: Set(live.keys)) == hidden)
        #expect(bar(memory) == [chevron, v1])
        let settled = OrderEditSettle.settledSections(
            edits, bar: bar(memory), live: Set(live.keys), concealed: hidden, roster: roster
        )
        #expect(settled.isEmpty)
        #expect(count(edits, bar: bar(memory)) == 1)
        // Drawn back instead, it is no edit, frames or not.
        var back = OrderEdits(
            order: [.hidden: [a, sound, snib]], previousOrder: [.hidden: [a, sound, snib]], dropped: [sound]
        )
        let backSettled = OrderEditSettle.settledSections(
            back, bar: bar(memory), live: Set(live.keys), concealed: hidden, roster: roster
        )
        #expect(backSettled == [.hidden])
        for section in backSettled { back.clearOrder(for: section) }
        #expect(count(back, bar: bar(memory)) == 0)
    }

    @Test func aForgottenFrameComesBackOnlyFromAWalkAtRest() {
        var memory = FrameMemory()
        memory.remember([a: frame(100), snib: frame(130)], chevronMidX: 210, atRest: true)
        memory.forget(allBut: [])
        #expect(memory.frames.isEmpty && memory.chevronMidX.isEmpty)
        // Mid-reveal, the walk reads the strip a part at a time.
        memory.remember([a: frame(90), snib: frame(140)], chevronMidX: 210, atRest: false)
        #expect(memory.frames.isEmpty)
        memory.remember([a: frame(100), snib: frame(150)], chevronMidX: 210, atRest: true)
        #expect(memory.frames == [a: frame(100), snib: frame(150)])
        #expect(memory.awaitingRest.isEmpty)
        // An icon no pass made stale is remembered from any walk, as before.
        memory.remember([sound: frame(170)], chevronMidX: 210, atRest: false)
        #expect(memory.frames[sound] == frame(170))
    }

    @Test func whatTheWalkAfterThePassReadsIsKept() {
        // Hidden out for the pass: the walk after the drags reads it all.
        var memory = FrameMemory()
        memory.remember([a: frame(100), snib: frame(130), sound: frame(160)], chevronMidX: 210, atRest: true)
        memory.remember([a: frame(100), sound: frame(130), snib: frame(160)], chevronMidX: 210, atRest: true)
        #expect(memory.forget(allBut: hidden).isEmpty)
        #expect(memory.frames[snib] == frame(160) && memory.chevronMidX[snib] == 210)
    }
}
