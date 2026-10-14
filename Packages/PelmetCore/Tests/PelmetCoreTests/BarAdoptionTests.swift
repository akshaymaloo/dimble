// BarAdoptionTests.swift
// Locks the ⌘-drag adoption rules: chevron gating, first-pass baseline,
// zone-change-only adoption, guessed-zone non-persistence, and the
// within-section order fold-in.

import CoreGraphics
import Testing
import PelmetCore

struct BarAdoptionTests {
    @Test func weTypeDraggedLeftOfChevronAdoptsHidden() {
        let input = ItemID.status(bundle: "com.apple.TextInputMenuAgent", title: "微信输入法")
        let result = BarAdoption.reconcile(
            items: [(id: anchor, minX: 2480), (id: input, minX: 2516), (id: chevron, minX: 2560)],
            model: SectionModel(assignments: [anchor.sectionKey: .hidden]),
            previousZones: [input.rawValue: .visible],
            pelmetBundleID: pelmet,
            draggedID: input
        )
        #expect(result?.model.section(of: input) == .hidden)
    }

    let pelmet = "app.fif7y.Pelmet"
    let chevron = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.StatusItem")
    let velja = ItemID(rawValue: "status:com.sindresorhus.Velja::Item-0")
    let figma = ItemID(rawValue: "status:com.figma.Desktop::Item-0")
    let anchor = ItemID(rawValue: "status:com.example.Anchor::Item-0")

    let sound = ItemID(rawValue: "status:com.apple.MenuBarAgent::com.apple.menuextra.sound")
    let siri = ItemID(rawValue: "status:com.apple.systemuiserver::Siri")

    @Test func systemExtraDraggedRightOfChevronAdoptsVisible() {
        // 2026-09-08: Sound ⌘-dragged right of the chevron kept hiding on
        // rehide — adoption skipped every com.apple. bundle, including the
        // extras the assertion can individually allow. Siri (unmanageable,
        // hard-pinned by the agent) must still be ignored.
        var model = SectionModel()
        model.assignments[sound.sectionKey] = .hidden
        model.assignments[siri.sectionKey] = .hidden
        model.order[.hidden] = [sound.sectionKey]
        model.order[.visible] = []
        let result = BarAdoption.reconcile(
            items: [
                (id: chevron, minX: 1421),
                (id: sound, minX: 1516),
                (id: siri, minX: 1657),
            ],
            model: model,
            previousZones: [sound.rawValue: .hidden],
            pelmetBundleID: pelmet,
            draggedID: sound
        )
        #expect(result?.changed == true)
        #expect(result?.model.assignments[sound.sectionKey] == nil)
        #expect(result?.model.order[.hidden] == [])
        #expect(result?.model.order[.visible] == [sound.sectionKey])
        #expect(result?.model.assignments[siri.sectionKey] == .hidden)
        #expect(result?.zones[siri.rawValue] == nil)
    }

    @Test func chevronDraggedLeftAdoptsTheCrossedItemsInOnePass() {
        // 2026-09-20: the chevron ⌘-dragged two slots left. Both icons now
        // right of it read Visible and were parked in "confirming on the
        // next pass"; the bar concealed them before any pass could agree,
        // and the next revealed pass voided the reading as a boundary move.
        // Nothing but the user moves the chevron: crossed items adopt now.
        let two = ItemID(rawValue: "status:com.example.Two::Item-0")
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .hidden
        model.assignments[two.sectionKey] = .hidden
        model.assignments[anchor.sectionKey] = .hidden
        model.order[.hidden] = [anchor.sectionKey, velja.sectionKey, two.sectionKey]
        let result = BarAdoption.reconcile(
            items: [
                (id: anchor, minX: 1400),
                (id: chevron, minX: 1449),
                (id: velja, minX: 1480),
                (id: two, minX: 1510),
                (id: figma, minX: 1540),
            ],
            model: model,
            previousZones: [anchor.rawValue: .hidden, velja.rawValue: .hidden, two.rawValue: .hidden, figma.rawValue: .visible],
            previousChevronX: 1529,
            userDragged: true,
            pelmetBundleID: pelmet,
            draggedID: chevron
        )
        #expect(result?.changed == true)
        #expect(result?.model.section(of: velja) == .visible)
        #expect(result?.model.section(of: two) == .visible)
        #expect(result?.model.section(of: anchor) == .hidden)
        #expect(result?.model.section(of: figma) == .visible)
        #expect(result?.pendingZones.isEmpty == true)
        #expect(result?.model.order[.hidden] == [anchor.sectionKey])
    }

    @Test func movedChevronReBaselinesInsteadOfAdopting() {
        // Figma, 2026-09-08: registered right of the chevron and adopted
        // Visible; on conceal Pelmet's extras right of the chevron folded and
        // the agent re-slotted the chevron past Figma (1427 → 1497, Figma
        // steady at 1465). The item never moved — no adoption, new baseline.
        var model = SectionModel()
        model.order[.visible] = [figma.sectionKey]
        let pass2 = BarAdoption.reconcile(
            items: [(id: figma, minX: 1465), (id: chevron, minX: 1497)],
            model: model,
            previousZones: [figma.rawValue: .visible],
            previousChevronX: 1427,
            pelmetBundleID: pelmet
        )
        #expect(pass2?.changed == false)
        #expect(pass2?.model.assignments[figma.sectionKey] == nil)
        // Collapsed bar: no hidden cluster measurable, so the reading is a
        // guess — the stale Visible baseline is dropped, not replaced.
        #expect(pass2?.zones[figma.rawValue] == nil)
        #expect(pass2?.chevronX == 1497)
        // Same bar again, chevron steady: still nothing to adopt.
        let pass3 = BarAdoption.reconcile(
            items: [(id: figma, minX: 1465), (id: chevron, minX: 1497)],
            model: model,
            previousZones: pass2!.zones,
            previousChevronX: pass2!.chevronX,
            pelmetBundleID: pelmet
        )
        #expect(pass3?.changed == false)
        // A ⌘-drag of the chevron itself IS a re-sectioning: adoption runs.
        let dragged = BarAdoption.reconcile(
            items: [(id: figma, minX: 1465), (id: chevron, minX: 1497)],
            model: model,
            previousZones: [figma.rawValue: .visible],
            previousChevronX: 1427,
            pelmetBundleID: pelmet,
            draggedID: chevron
        )
        #expect(dragged?.model.assignments[figma.sectionKey] == .hidden)
        // The item itself travelled since the last pass (a ⌘-drag the band
        // monitor's drop x missed): it adopts even though the chevron moved.
        let travelled = BarAdoption.reconcile(
            items: [(id: figma, minX: 1417), (id: chevron, minX: 1497)],
            model: model,
            previousZones: [figma.rawValue: .visible],
            previousChevronX: 1459,
            previousPositions: [figma.rawValue: 1535],
            userDragged: true,
            pelmetBundleID: pelmet
        )
        #expect(travelled?.model.assignments[figma.sectionKey] == .hidden)
        #expect(travelled?.positions[figma.rawValue] == 1417)
        // The same travel without a user drag is Pelmet's own placement
        // (an editor drop): the boundary guard holds (0.2.17 regression —
        // every editor drop adopted the item into Always Hidden).
        let placed = BarAdoption.reconcile(
            items: [(id: figma, minX: 1417), (id: chevron, minX: 1497)],
            model: model,
            previousZones: [figma.rawValue: .visible],
            previousChevronX: 1459,
            previousPositions: [figma.rawValue: 1535],
            pelmetBundleID: pelmet
        )
        #expect(placed?.changed == false)
        #expect(placed?.model.assignments[figma.sectionKey] == nil)
    }

    @Test func missingChevronSkipsZoneAdoptionButStillFoldsOrder() {
        // The user can hide Pelmet's status item — no boundary, so zones
        // must not move, but a bar ⌘-drag still reorders within a section.
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .hidden
        model.assignments[figma.sectionKey] = .hidden
        model.order[.hidden] = [velja.sectionKey, figma.sectionKey]
        let result = BarAdoption.reconcile(
            items: [
                (id: velja, minX: 500),
                (id: figma, minX: 400),
            ],
            model: model,
            previousZones: [velja.rawValue: .hidden, figma.rawValue: .hidden],
            pelmetBundleID: pelmet
        )
        #expect(result?.model.order[.hidden] == [figma.sectionKey, velja.sectionKey])
        #expect(result?.model.assignments[velja.sectionKey] == .hidden)
        #expect(result?.zones == [velja.rawValue: .hidden, figma.rawValue: .hidden])
    }

    @Test func noChevronDropInsideVisibleClusterAdoptsVisible() {
        // The Vorssaint case (2026-08-31): icon hidden, full reveal, an
        // always-hidden item ⌘-dragged in among the visible cluster must
        // adopt visible — the cluster's left edge is the implicit boundary.
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .alwaysHidden
        let result = BarAdoption.reconcile(
            items: [
                (id: anchor, minX: 900),   // visible cluster member
                (id: velja, minX: 950),    // dropped to its right
            ],
            model: model,
            previousZones: [velja.rawValue: .alwaysHidden, anchor.rawValue: .visible],
            pelmetBundleID: pelmet,
            draggedID: velja
        )
        #expect(result?.changed == true)
        #expect(result?.model.assignments[velja.sectionKey] == nil)
        #expect(result?.zones[velja.rawValue] == .visible)
        // The dragged item's stale model entry poisons the neighbor's reading
        // (anchor sits left of a "concealable" at 950) — but only the dragged
        // item may adopt without a chevron, so anchor must not move.
        #expect(result?.model.assignments[anchor.sectionKey] == nil)
    }

    @Test func noChevronDropInsideConcealableClusterAdoptsHidden() {
        var model = SectionModel()
        model.assignments[figma.sectionKey] = .hidden
        model.assignments[anchor.sectionKey] = .hidden
        let result = BarAdoption.reconcile(
            items: [
                (id: figma, minX: 300),
                (id: anchor, minX: 400),
                (id: velja, minX: 350),    // visible item dropped mid-cluster
            ],
            model: model,
            previousZones: [
                velja.rawValue: .visible,
                figma.rawValue: .hidden,
                anchor.rawValue: .hidden,
            ],
            pelmetBundleID: pelmet,
            draggedID: velja
        )
        #expect(result?.changed == true)
        #expect(result?.model.assignments[velja.sectionKey] == .hidden)
    }

    @Test func noChevronDraggedItemAdoptsWithoutABaseline() {
        // Fresh boot: no revealed pass ran before the drag, so the dragged
        // item has no baseline — the gesture is the evidence and a confident
        // reading must adopt anyway (observed live 2026-08-31 22:26).
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .hidden
        model.assignments[figma.sectionKey] = .alwaysHidden
        model.assignments[anchor.sectionKey] = .alwaysHidden
        let result = BarAdoption.reconcile(
            items: [
                (id: figma, minX: 300),
                (id: velja, minX: 350),    // dropped mid always-hidden cluster
                (id: anchor, minX: 400),
            ],
            model: model,
            previousZones: [:],
            pelmetBundleID: pelmet,
            draggedID: velja
        )
        #expect(result?.changed == true)
        #expect(result?.model.assignments[velja.sectionKey] == .alwaysHidden)
    }

    @Test func noChevronWithoutDraggedIDNeitherAdoptsNorEatsTheDrag() {
        // Order-change passes fire DURING a drag with no dragged id — they
        // must neither adopt nor fold the moved item's new side into the
        // baseline, or the drag-end pass would see previousZone == zone and
        // skip the adoption.
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .alwaysHidden
        let result = BarAdoption.reconcile(
            items: [
                (id: anchor, minX: 900),
                (id: velja, minX: 950),
            ],
            model: model,
            previousZones: [velja.rawValue: .alwaysHidden, anchor.rawValue: .visible],
            pelmetBundleID: pelmet
        )
        #expect(result?.model.assignments[velja.sectionKey] == .alwaysHidden)
        #expect(result?.zones[velja.rawValue] == .alwaysHidden)
    }

    @Test func noChevronLeftmostVisibleMemberIsNotFalseAdopted() {
        // The leftmost visible item always reads left of every OTHER visible
        // member; without a chevron that gap must stay ambiguous, never a
        // demotion to hidden.
        var model = SectionModel()
        model.assignments[figma.sectionKey] = .hidden
        let result = BarAdoption.reconcile(
            items: [
                (id: figma, minX: 300),
                (id: anchor, minX: 500),   // leftmost visible
                (id: velja, minX: 600),    // second visible
            ],
            model: model,
            previousZones: [
                anchor.rawValue: .visible,
                velja.rawValue: .visible,
                figma.rawValue: .hidden,
            ],
            pelmetBundleID: pelmet
        )
        #expect(result?.changed == false)
        #expect(result?.model.assignments[anchor.sectionKey] == nil)
        #expect(result?.zones[anchor.rawValue] == .visible)
    }

    @Test func firstPassBaselinesZonesWithoutAdopting() {
        let result = BarAdoption.reconcile(
            items: [(id: chevron, minX: 1000), (id: velja, minX: 1100)],
            model: SectionModel(),
            previousZones: [:],
            pelmetBundleID: pelmet
        )
        #expect(result?.changed == false)
        #expect(result?.zones[velja.rawValue] == .visible)
        #expect(result?.model.assignments.isEmpty == true)
    }

    /// A non-dragged zone change adopts on the second agreeing pass.
    func twoPasses(items: [(id: ItemID, minX: CGFloat?)], model: SectionModel, previousZones: [String: Section]) -> BarAdoption.Result? {
        let first = BarAdoption.reconcile(items: items, model: model, previousZones: previousZones, pelmetBundleID: pelmet)
        return BarAdoption.reconcile(
            items: items, model: model,
            previousZones: first?.zones ?? previousZones, pendingZones: first?.pendingZones ?? [:],
            pelmetBundleID: pelmet
        )
    }

    @Test func zoneChangeAdoptsIntoHidden() {
        var model = SectionModel()
        model.assignments[anchor.sectionKey] = .hidden
        let items: [(id: ItemID, minX: CGFloat?)] = [(chevron, 1000), (anchor, 400), (velja, 500)]
        let first = BarAdoption.reconcile(
            items: items, model: model,
            previousZones: [velja.rawValue: .visible, anchor.rawValue: .hidden],
            pelmetBundleID: pelmet
        )
        #expect(first?.changed == false)
        #expect(first?.pendingZones[velja.rawValue] == .hidden)
        let result = twoPasses(items: items, model: model, previousZones: [velja.rawValue: .visible, anchor.rawValue: .hidden])
        #expect(result?.changed == true)
        #expect(result?.model.assignments[velja.sectionKey] == .hidden)
        #expect(result?.zones[velja.rawValue] == .hidden)
    }

    @Test func zoneChangeAdoptsBackToVisible() {
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .hidden
        let result = twoPasses(
            items: [(chevron, 1000), (velja, 1200)], model: model,
            previousZones: [velja.rawValue: .hidden]
        )
        #expect(result?.changed == true)
        #expect(result?.model.assignments[velja.sectionKey] == nil)
    }

    @Test func draggedLeftmostHiddenMemberAdoptsAlwaysHiddenWithoutABaseline() {
        // The Sconce case (2026-09-05): the LEFTMOST hidden member never
        // earns a confident baseline — self-excluded, it always reads
        // "between the clusters" — so the zone-change rule could never fire
        // for it. The ⌘-drag itself is the evidence: a confident reading of
        // the dragged item adopts with a chevron too.
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .hidden          // Sconce stand-in
        model.assignments[figma.sectionKey] = .hidden          // Snib stand-in
        model.assignments[anchor.sectionKey] = .alwaysHidden   // trailing AH separator
        model.order[.hidden] = [velja.sectionKey, figma.sectionKey]
        model.order[.alwaysHidden] = [anchor.sectionKey]
        let result = BarAdoption.reconcile(
            items: [
                (id: chevron, minX: 1000),
                (id: figma, minX: 430),
                (id: anchor, minX: 370),
                (id: velja, minX: 340),   // dropped LEFT of the AH cluster's right edge
            ],
            model: model,
            previousZones: [figma.rawValue: .hidden, anchor.rawValue: .alwaysHidden],
            pelmetBundleID: pelmet,
            draggedID: velja
        )
        #expect(result?.changed == true)
        #expect(result?.model.assignments[velja.sectionKey] == .alwaysHidden)
        #expect(result?.zones[velja.rawValue] == .alwaysHidden)
        // The dragged item's stale .hidden entry must not stretch the hidden
        // cluster over the AH separator it landed left of.
        #expect(result?.model.assignments[anchor.sectionKey] == .alwaysHidden)
        #expect(result?.model.order[.hidden] == [figma.sectionKey])
        #expect(result?.model.order[.alwaysHidden] == [velja.sectionKey, anchor.sectionKey])
    }

    @Test func draggedItemBetweenClustersKeepsTheModelsWord() {
        // Dropped right of the AH cluster and left of the hidden one: still
        // ambiguous even for the dragged item — no boundary to judge against.
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .hidden
        model.assignments[figma.sectionKey] = .hidden
        model.assignments[anchor.sectionKey] = .alwaysHidden
        let result = BarAdoption.reconcile(
            items: [
                (id: chevron, minX: 1000),
                (id: figma, minX: 430),
                (id: velja, minX: 400),
                (id: anchor, minX: 370),
            ],
            model: model,
            previousZones: [figma.rawValue: .hidden, anchor.rawValue: .alwaysHidden],
            pelmetBundleID: pelmet,
            draggedID: velja
        )
        #expect(result?.model.assignments[velja.sectionKey] == .hidden)
        #expect(result?.zones[velja.rawValue] == nil)
    }

    @Test func ambiguousZoneConservesModelAndDoesNotPersist() {
        // No measurable hidden/always-hidden cluster besides the item itself
        // → ambiguous; the model's word stands and the guess is not tracked.
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .hidden
        let result = BarAdoption.reconcile(
            items: [(id: chevron, minX: 1000), (id: velja, minX: 300)],
            model: model,
            previousZones: [velja.rawValue: .visible],
            pelmetBundleID: pelmet
        )
        #expect(result?.changed == false)
        #expect(result?.zones[velja.rawValue] == .visible)
        #expect(result?.model.assignments[velja.sectionKey] == .hidden)
    }

    @Test func liveOrderFoldsBackIntoExplicitOrder() {
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .hidden
        model.assignments[figma.sectionKey] = .hidden
        model.order[.hidden] = [velja.sectionKey, figma.sectionKey]
        let result = BarAdoption.reconcile(
            items: [
                (id: chevron, minX: 1000),
                (id: velja, minX: 500),
                (id: figma, minX: 400),
            ],
            model: model,
            previousZones: [velja.rawValue: .hidden, figma.rawValue: .hidden],
            pelmetBundleID: pelmet
        )
        #expect(result?.changed == true)
        #expect(result?.model.order[.hidden] == [figma.sectionKey, velja.sectionKey])
        #expect(result?.log.contains("adopt: hidden order reconciled from bar") == true)
    }

    @Test func ownItemHoldsItsModelSlotUnlessDragged() {
        let launcher = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.App.ABCD")
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .hidden
        model.assignments[figma.sectionKey] = .hidden
        model.assignments[launcher.sectionKey] = .hidden
        model.order[.hidden] = [velja.sectionKey, figma.sectionKey, launcher.sectionKey]
        let items: [(id: ItemID, minX: CGFloat?)] = [
            (id: chevron, minX: 1000),
            (id: velja, minX: 400),
            // Re-entered layout between its neighbors — not the user's doing.
            (id: launcher, minX: 450),
            (id: figma, minX: 500),
        ]
        let zones = [velja.rawValue: Section.hidden, figma.rawValue: .hidden, launcher.rawValue: .hidden]
        let held = BarAdoption.reconcile(
            items: items, model: model, previousZones: zones, pelmetBundleID: pelmet
        )
        #expect(held?.model.order[.hidden] == [velja.sectionKey, figma.sectionKey, launcher.sectionKey])
        let dragged = BarAdoption.reconcile(
            items: items, model: model, previousZones: zones, pelmetBundleID: pelmet, draggedID: launcher
        )
        #expect(dragged?.model.order[.hidden] == [velja.sectionKey, launcher.sectionKey, figma.sectionKey])
    }

    // Live test, 2026-10-13: an icon ⌘-dragged past one of Pelmet's own
    // items left the third-party order as it was, so nothing was adopted.
    @Test func draggedIconPastAnOwnItemTakesItsSlotAmongThem() {
        let media = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.MediaControls")
        var model = SectionModel()
        model.order[.visible] = [velja.sectionKey, media.sectionKey, figma.sectionKey]
        let items: [(id: ItemID, minX: CGFloat?)] = [
            (id: chevron, minX: 1000), (id: media, minX: 1040), (id: velja, minX: 1080), (id: figma, minX: 1120),
        ]
        let zones = [velja.rawValue: Section.visible, figma.rawValue: .visible, media.rawValue: .visible]
        let dragged = BarAdoption.reconcile(
            items: items, model: model, previousZones: zones, userDragged: true, pelmetBundleID: pelmet, draggedID: velja
        )
        #expect(dragged?.changed == true)
        #expect(dragged?.model.order[.visible] == [media.sectionKey, velja.sectionKey, figma.sectionKey])
        // Not dragged, the own item still holds its slot.
        let held = BarAdoption.reconcile(items: items, model: model, previousZones: zones, pelmetBundleID: pelmet)
        #expect(held?.model.order[.visible] == [velja.sectionKey, media.sectionKey, figma.sectionKey])
    }

    @Test func draggedIconLandsAfterItsBarNeighbourWhenOwnItemsSitOutOfOrder() {
        // Shortcuts holds its slot at the end of the drawing but sits first
        // on the bar: it is no left neighbour of A (review, 2026-10-13).
        let shortcuts = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.Shortcuts")
        let (a, b, c, d) = (velja, figma, anchor, ItemID(rawValue: "status:com.example.D::Item-0"))
        var model = SectionModel()
        for id in [a, b, c, d, shortcuts] { model.assignments[id.sectionKey] = .hidden }
        model.order[.hidden] = [a, b, c, d, shortcuts].map(\.sectionKey)
        let result = BarAdoption.reconcile(
            items: [(id: shortcuts, minX: 300), (id: b, minX: 340), (id: a, minX: 380),
                    (id: c, minX: 420), (id: d, minX: 460), (id: chevron, minX: 1000)],
            model: model, previousZones: [a.rawValue: .hidden], userDragged: true,
            pelmetBundleID: pelmet, draggedID: a
        )
        #expect(result?.model.order[.hidden] == [b, a, c, d, shortcuts].map(\.sectionKey))
    }

    @Test func draggedIconWithNoLeftNeighbourGoesBeforeItsRightOne() {
        let shortcuts = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.Shortcuts")
        var model = SectionModel()
        for id in [velja, figma, shortcuts] { model.assignments[id.sectionKey] = .hidden }
        model.order[.hidden] = [shortcuts, figma, velja].map(\.sectionKey)
        let result = BarAdoption.reconcile(
            items: [(id: velja, minX: 300), (id: figma, minX: 340), (id: shortcuts, minX: 380), (id: chevron, minX: 1000)],
            model: model, previousZones: [velja.rawValue: .hidden], userDragged: true,
            pelmetBundleID: pelmet, draggedID: velja
        )
        #expect(result?.model.order[.hidden] == [shortcuts, velja, figma].map(\.sectionKey))
    }

    @Test func draggedIconWithNoFramedNeighbourKeepsItsSlot() {
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .hidden
        model.assignments[figma.sectionKey] = .hidden
        model.order[.hidden] = [figma.sectionKey, velja.sectionKey]
        let result = BarAdoption.reconcile(
            items: [(id: chevron, minX: 1000), (id: velja, minX: 900), (id: figma, minX: nil)],
            model: model, previousZones: [velja.rawValue: .hidden], userDragged: true,
            pelmetBundleID: pelmet, draggedID: velja
        )
        #expect(result?.model.order[.hidden] == [figma.sectionKey, velja.sectionKey])
    }

    @Test func helperHostedOwnItemHoldsItsModelSlotToo() {
        // A hidden-section separator is drawn by the hidden helper: its live
        // id carries the helper bundle, its key folds to the main bundle.
        let live = ItemID(rawValue: "status:app.fif7y.Pelmet.items.hidden::Pelmet.Separator.S1")
        let key = live.sectionKey
        #expect(key == ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.Separator.S1"))
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .hidden
        model.assignments[figma.sectionKey] = .hidden
        model.assignments[key] = .hidden
        model.order[.hidden] = [velja.sectionKey, figma.sectionKey, key]
        let items: [(id: ItemID, minX: CGFloat?)] = [
            (id: chevron, minX: 1000),
            (id: velja, minX: 400),
            (id: live, minX: 450),
            (id: figma, minX: 500),
        ]
        let zones = [velja.rawValue: Section.hidden, figma.rawValue: .hidden, live.rawValue: .hidden]
        let held = BarAdoption.reconcile(
            items: items, model: model, previousZones: zones, pelmetBundleID: pelmet
        )
        #expect(held?.model.order[.hidden] == [velja.sectionKey, figma.sectionKey, key])
        let dragged = BarAdoption.reconcile(
            items: items, model: model, previousZones: zones, pelmetBundleID: pelmet, draggedID: live
        )
        #expect(dragged?.model.order[.hidden] == [velja.sectionKey, key, figma.sectionKey])
    }

    @Test func sectionChangedEntryDropsOutOfOrder() {
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .hidden
        model.assignments[figma.sectionKey] = .alwaysHidden
        model.order[.hidden] = [velja.sectionKey, figma.sectionKey]
        let result = BarAdoption.reconcile(
            items: [(id: chevron, minX: 1000)],
            model: model,
            previousZones: [velja.rawValue: .hidden],
            pelmetBundleID: pelmet
        )
        #expect(result?.changed == true)
        #expect(result?.model.order[.hidden] == [velja.sectionKey])
    }

    @Test func liveNewcomerInsertsByX() {
        var model = SectionModel()
        model.assignments[velja.sectionKey] = .hidden
        model.assignments[figma.sectionKey] = .hidden
        model.order[.hidden] = [velja.sectionKey]
        let result = BarAdoption.reconcile(
            items: [
                (id: chevron, minX: 1000),
                (id: velja, minX: 500),
                (id: figma, minX: 400),
            ],
            model: model,
            previousZones: [velja.rawValue: .hidden, figma.rawValue: .hidden],
            pelmetBundleID: pelmet
        )
        #expect(result?.changed == true)
        #expect(result?.model.order[.hidden] == [figma.sectionKey, velja.sectionKey])
    }

    // Gab's bar, 2026-09-25: One Thing ⌘-dragged in right of Media went to
    // the front of Visible, and Camera held a slot after the clock.
    @Test func newcomerSlotsAgainstOwnItemsAndThePinnedEndStaysLast() {
        let media = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.MediaControls")
        let camera = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.CameraMic")
        let cc = ItemID.status(bundle: "com.apple.MenuBarAgent", title: "com.apple.menuextra.controlcenter")
        let clock = ItemID.status(bundle: "com.apple.MenuBarAgent", title: "com.apple.menuextra.clock")
        var model = SectionModel()
        model.order[.visible] = [media.sectionKey, cc.sectionKey, clock.sectionKey, camera.sectionKey]
        let result = BarAdoption.reconcile(
            items: [
                (id: chevron, minX: 1399), (id: media, minX: 1437), (id: velja, minX: 1475),
                (id: camera, minX: 1599), (id: cc, minX: 1645), (id: clock, minX: 1684),
            ],
            model: model,
            previousZones: [velja.rawValue: .visible],
            pelmetBundleID: pelmet
        )
        #expect(result?.model.order[.visible] == [
            media.sectionKey, velja.sectionKey, camera.sectionKey, cc.sectionKey, clock.sectionKey,
        ])
    }
}

extension BarAdoptionTests {
    @Test func zoneChangeWithoutDragNeedsTwoAgreeingPasses() {
        // 2026-09-09: a pass that landed while a full reveal collapsed read
        // three hidden items inside the always-hidden cluster and adopted
        // them in one go. A non-dragged change now waits for the next pass.
        var model = SectionModel()
        model.assignments[anchor.sectionKey] = .alwaysHidden
        model.assignments[velja.sectionKey] = .hidden
        model.order[.alwaysHidden] = [anchor.sectionKey]
        model.order[.hidden] = [velja.sectionKey]
        // Velja reads inside the always-hidden cluster (left of its member).
        let items = [(id: anchor, minX: CGFloat(1200)), (id: velja, minX: CGFloat(1180)), (id: chevron, minX: CGFloat(1421))]
        let first = BarAdoption.reconcile(
            items: items, model: model,
            previousZones: [velja.rawValue: .hidden, anchor.rawValue: .alwaysHidden],
            pelmetBundleID: pelmet
        )
        #expect(first?.model.assignments[velja.sectionKey] == .hidden)
        #expect(first?.pendingZones[velja.rawValue] == .alwaysHidden)
        #expect(first?.zones[velja.rawValue] == .hidden)
        // The reading flips back: nothing adopts, the candidate is dropped.
        let flipped = BarAdoption.reconcile(
            items: [(id: anchor, minX: 1200), (id: velja, minX: 1300), (id: chevron, minX: 1421)],
            model: model,
            previousZones: first!.zones, pendingZones: first!.pendingZones,
            pelmetBundleID: pelmet
        )
        #expect(flipped?.model.assignments[velja.sectionKey] == .hidden)
        #expect(flipped?.pendingZones[velja.rawValue] == nil)
        // Two agreeing passes adopt.
        let second = BarAdoption.reconcile(
            items: items, model: model,
            previousZones: first!.zones, pendingZones: first!.pendingZones,
            pelmetBundleID: pelmet
        )
        #expect(second?.model.assignments[velja.sectionKey] == .alwaysHidden)
        #expect(second?.pendingZones[velja.rawValue] == nil)
    }

    @Test func ownExtraAbsentFromOrderFoldsInByBarX() {
        // #13 (2026-09-14): media controls toggled on never entered
        // order[.visible] (the toggle appends the spec, not its key — only
        // launchers do both), so the fold-in listed it as missing and looked
        // it up in `liveX`, which keeps Pelmet's own items out on purpose:
        // a force-unwrapped nil, a trap on the first adopt pass of every
        // launch. Two such extras exercise the sort comparator as well.
        let media = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.MediaControls")
        let camera = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.CameraMic")
        let battery = ItemID(rawValue: "status:com.apple.MenuBarAgent::com.apple.menuextra.battery")
        let clock = ItemID(rawValue: "status:com.apple.MenuBarAgent::com.apple.menuextra.clock")
        var model = SectionModel()
        model.order[.visible] = [battery.sectionKey, clock.sectionKey]
        let result = BarAdoption.reconcile(
            items: [
                (id: camera, minX: 1170),
                (id: media, minX: 1195),
                (id: chevron, minX: 1233),
                (id: battery, minX: 1241),
                (id: clock, minX: 1403),
            ],
            model: model,
            previousZones: [:],
            pelmetBundleID: pelmet
        )
        #expect(result?.changed == true)
        #expect(result?.model.order[.visible]
            == [camera.sectionKey, media.sectionKey, battery.sectionKey, clock.sectionKey])
    }

    @Test func refillKeepsOffBarMembersInTheirSlots() {
        // Hidden while concealed (2026-09-25): Pelmet's Siri has left the
        // layout, the apps have remembered frames. Siri stays second.
        let passwords = ItemID(rawValue: "bundle:com.apple.Passwords.MenuBarExtra")
        let siri = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.Siri")
        let utils = ItemID(rawValue: "bundle:com.vorssaint.utils")
        let weather = ItemID(rawValue: "bundle:com.apple.weather.menu")
        let snib = ItemID(rawValue: "bundle:app.fif7y.Snib")
        let chevron = ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.StatusItem")
        #expect(BarAdoption.refill([passwords, siri, utils, weather, snib], inBarOrder: [passwords, utils, weather, snib, chevron])
            == [passwords, siri, utils, weather, snib])
        // The framed members still take the bar's order around it.
        #expect(BarAdoption.refill([passwords, siri, utils, weather, snib], inBarOrder: [utils, passwords, snib, weather])
            == [utils, siri, passwords, snib, weather])
    }

    // Live test 2026-10-13 19:29:50: the BenQ left (bar at y=-113), the
    // built-in main, the LG ultrawide right. The LG shows every section;
    // Vorssaint, drawn into Hidden, ⌘-dragged by hand on the LG's bar
    // before Snib. The walk keeps the built-in's copies.
    var builtIn: CGRect { CGRect(x: 0, y: 0, width: 1800, height: 1169) }
    var lg: CGRect { CGRect(x: 1800, y: 0, width: 3440, height: 1440) }
    var benq: CGRect { CGRect(x: -1920, y: -113, width: 1920, height: 1080) }
    var utils: ItemID { ItemID(rawValue: "status:com.vorssaint.utils::Item-0") }
    var snib: ItemID { ItemID(rawValue: "status:app.fif7y.Snib::Item-0") }
    var shortcuts: ItemID { ItemID(rawValue: "status:app.fif7y.Pelmet::Pelmet.Shortcuts") }
    var clock: ItemID { ItemID(rawValue: "status:com.apple.MenuBarAgent::com.apple.menuextra.clock") }

    func icon(_ x: CGFloat, y: CGFloat = 0) -> CGRect { CGRect(x: x, y: y, width: 24, height: 24) }

    /// The walk (one copy each, the built-in's where it has one; Hidden is
    /// concealed there) and every display's copies.
    var lgDrop: (items: [(id: ItemID, frame: CGRect?)], copies: [ItemID: [CGRect]]) {
        let copies: [ItemID: [CGRect]] = [
            shortcuts: [icon(4900), icon(-400, y: -113)],
            utils: [icon(4928), icon(-372, y: -113)],
            snib: [icon(4960), icon(-340, y: -113)],
            sound: [icon(4990), icon(-310, y: -113)],
            chevron: [icon(1601), icon(5020), icon(-280, y: -113)],
            clock: [icon(1700), icon(5100), icon(-200, y: -113)],
        ]
        let items: [(id: ItemID, frame: CGRect?)] = [
            (shortcuts, icon(-400, y: -113)), (utils, icon(4928)), (snib, icon(4960)),
            (sound, icon(4990)), (chevron, icon(1601)), (clock, icon(1700)),
        ]
        return (items, copies)
    }

    @Test func aDropOnAnotherDisplaysBarReadsThatBar() {
        let (items, copies) = lgDrop
        let bar = BarAdoption.dropBar(items: items, copies: copies, display: lg, primaryMaxX: builtIn.maxX)
        #expect(bar.map(\.id) == items.map(\.id))
        #expect(bar.map { $0.frame?.minX } == [4900, 4928, 4960, 4990, 5020, 5100])
        #expect(BarAdoption.droppedItem(at: 4920, on: bar, grabbed: "com.vorssaint.utils", grabbedOnly: true) == utils)
        #expect(BarAdoption.barOrder(bar) == [shortcuts, utils, snib, sound, chevron, clock].map(\.sectionKey))
        // Read on the built-in, as before: nothing under the drop, and only
        // the built-in's chevron and clock are measured.
        let main = BarAdoption.dropBar(items: items, copies: copies, display: nil, primaryMaxX: builtIn.maxX)
        #expect(main.map { $0.frame?.minX } == [nil, nil, nil, nil, 1601, 1700])
        #expect(BarAdoption.droppedItem(at: 4920, on: main, grabbed: "com.vorssaint.utils") == nil)
        // The BenQ's bar is a bar of its own too.
        let left = BarAdoption.dropBar(items: items, copies: copies, display: benq, primaryMaxX: builtIn.maxX)
        #expect(BarAdoption.droppedItem(at: -366, on: left, grabbed: nil) == utils)
        // A display that lists no copy reads nothing.
        let none = BarAdoption.dropBar(items: items, copies: [:], display: lg, primaryMaxX: builtIn.maxX)
        #expect(none.allSatisfy { $0.frame == nil })
    }

    @Test func aDropOnAnotherDisplayCreditsTheGrabbedAppsOnlyIconAFewPointsOff() {
        // Snib landed 15pt right of the pointer on the LG (live test,
        // 2026-10-13 21:54:43); Vorssaint, under the pointer, isn't Snib.
        let (items, copies) = lgDrop
        let bar = BarAdoption.dropBar(items: items, copies: copies, display: lg, primaryMaxX: builtIn.maxX)
        #expect(BarAdoption.droppedItem(at: 4945, on: bar, grabbed: "app.fif7y.Snib", grabbedOnly: true) == nil)
        #expect(BarAdoption.droppedItem(at: 4945, on: bar, grabbed: "app.fif7y.Snib", grabbedOnly: true, soleGrabbedSlack: 24) == snib)
        // Further off than the slack: nobody.
        #expect(BarAdoption.droppedItem(at: 4920, on: bar, grabbed: "app.fif7y.Snib", grabbedOnly: true, soleGrabbedSlack: 24) == nil)
        // An app with two icons there (Apple's host): which one is a guess.
        #expect(BarAdoption.droppedItem(at: 4975, on: bar, grabbed: "com.apple.MenuBarAgent", grabbedOnly: true, soleGrabbedSlack: 24) == nil)
    }

    @Test func theDropLandsAsTheGrabbedAppsIcon() {
        let bar: [(id: ItemID, frame: CGRect?)] = [(chevron, icon(1500)), (figma, icon(1520))]
        // The chevron sits nearer the drop; the grabbed app wins.
        #expect(BarAdoption.droppedItem(at: 1515, on: bar, grabbed: "com.figma.Desktop") == figma)
        #expect(BarAdoption.droppedItem(at: 1515, on: bar, grabbed: nil) == chevron)
        // Landed only once the grabbed app's icon is under it: a neighbour
        // there is the drop animation still running.
        #expect(BarAdoption.droppedItem(at: 1495, on: bar, grabbed: "com.figma.Desktop") == chevron)
        #expect(BarAdoption.droppedItem(at: 1495, on: bar, grabbed: "com.figma.Desktop", grabbedOnly: true) == nil)
        #expect(BarAdoption.droppedItem(at: 1495, on: bar, grabbed: nil, grabbedOnly: true) == chevron)
        #expect(BarAdoption.droppedItem(at: 1600, on: bar, grabbed: nil) == nil)
    }

    @Test func aDragOnTheLGsBarFoldsInAgainstItsChevron() {
        let (items, copies) = lgDrop
        var model = SectionModel(assignments: [
            shortcuts.sectionKey: .hidden, utils.sectionKey: .hidden,
            snib.sectionKey: .hidden, sound.sectionKey: .hidden,
        ])
        model.order[.hidden] = [shortcuts, snib, utils, sound].map(\.sectionKey)
        let bar = BarAdoption.dropBar(items: items, copies: copies, display: lg, primaryMaxX: builtIn.maxX)
        let result = BarAdoption.reconcile(
            items: bar.map { (id: $0.id, minX: $0.frame?.minX) },
            model: model,
            previousZones: [utils.rawValue: .hidden, snib.rawValue: .hidden, sound.rawValue: .hidden, clock.rawValue: .visible],
            userDragged: true,
            pelmetBundleID: pelmet,
            draggedID: BarAdoption.droppedItem(at: 4920, on: bar, grabbed: "com.vorssaint.utils")
        )
        #expect(result?.chevronX == 5020)
        #expect(result?.model.section(of: utils) == .hidden)
        #expect(result?.model.order[.hidden] == [shortcuts, utils, snib, sound].map(\.sectionKey))
        #expect(result?.changed == true)
    }
}
