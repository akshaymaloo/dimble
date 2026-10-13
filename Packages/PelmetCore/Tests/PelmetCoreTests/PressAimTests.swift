// PressAimTests.swift
// Where a press made from another display clicks (#26): the item's own copy
// on that bar by full id, never a sibling icon of the same app, never a
// phantom behind that bar's «, and a settle that only agrees within one bar.

import CoreGraphics
import Testing
import PelmetCore

struct PressAimTests {
    // Gab's three displays in CG global space.
    let builtIn = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    let benQ = CGRect(x: -2560, y: -113, width: 2560, height: 1440)
    let lg = CGRect(x: 1800, y: 0, width: 3440, height: 1440)

    let statsCPU = ItemID.status(bundle: "eu.exelban.Stats", title: "CPU")
    let statsRAM = ItemID.status(bundle: "eu.exelban.Stats", title: "RAM")

    @Test func aMultiIconAppIsAimedByFullIDNotBySectionKey() {
        #expect(statsCPU.sectionKey == statsRAM.sectionKey)
        let cpuMain = CGRect(x: 1200, y: 0, width: 40, height: 39)
        let ramMain = CGRect(x: 1240, y: 0, width: 40, height: 39)
        let cpuLG = CGRect(x: 4500, y: 0, width: 40, height: 30)
        let ramLG = CGRect(x: 4540, y: 0, width: 40, height: 30)
        let copies = [statsCPU: [cpuMain, cpuLG], statsRAM: [ramMain, ramLG]]
        // Whatever order the dictionary walks in, each icon gets its own copy.
        for _ in 0..<50 {
            let shuffled = Dictionary(uniqueKeysWithValues: copies.shuffled())
            #expect(PressAim.aim(id: statsCPU, main: cpuMain, display: lg, copies: shuffled)
                == PressAim(frame: cpuLG, onPressDisplay: true))
            #expect(PressAim.aim(id: statsRAM, main: ramMain, display: lg, copies: shuffled)
                == PressAim(frame: ramLG, onPressDisplay: true))
        }
    }

    @Test func noCopyOnThePressDisplayFallsBackToTheMainOne() {
        let main = CGRect(x: 1200, y: 0, width: 40, height: 39)
        let benQCopy = CGRect(x: -900, y: -113, width: 40, height: 30)
        let copies = [statsCPU: [main, benQCopy]]
        #expect(PressAim.aim(id: statsCPU, main: main, display: lg, copies: copies)
            == PressAim(frame: main, onPressDisplay: false))
        #expect(PressAim.aim(id: statsCPU, main: main, display: benQ, copies: copies)
            == PressAim(frame: benQCopy, onPressDisplay: true))
        #expect(PressAim.aim(id: statsCPU, main: main, display: nil, copies: copies)
            == PressAim(frame: main, onPressDisplay: false))
        // A sibling's copy on the LG is never this icon's.
        #expect(PressAim.aim(id: statsCPU, main: main, display: lg, copies: [statsCPU: [main], statsRAM: [CGRect(x: 4540, y: 0, width: 40, height: 30)]])
            == PressAim(frame: main, onPressDisplay: false))
    }

    @Test func aCopyBehindThePressDisplaysOverflowIsNotAimedAt() {
        let main = CGRect(x: 1200, y: 0, width: 40, height: 39)
        // The « holds both: their frames overlap by 30pt.
        let phantom = CGRect(x: 2000, y: 0, width: 36, height: 30)
        let neighbour = CGRect(x: 2006, y: 0, width: 36, height: 30)
        let copies = [statsCPU: [main, phantom], statsRAM: [neighbour]]
        #expect(PressAim.aim(id: statsCPU, main: main, display: lg, copies: copies)
            == PressAim(frame: main, onPressDisplay: false))
        // Real neighbours touch by AX padding only.
        let beside = CGRect(x: 2034, y: 0, width: 36, height: 30)
        #expect(PressAim.aim(id: statsCPU, main: main, display: lg, copies: [statsCPU: [main, phantom], statsRAM: [beside]])
            == PressAim(frame: phantom, onPressDisplay: true))
    }

    @Test func aBarIsListedOnlyWhereItsDisplayDrawsCopies() {
        let copies = [statsCPU: [CGRect(x: 1200, y: 0, width: 40, height: 39), CGRect(x: 4500, y: 0, width: 40, height: 30)]]
        #expect(PressAim.barListed(on: lg, copies: copies))
        #expect(PressAim.barListed(on: builtIn, copies: copies))
        #expect(!PressAim.barListed(on: benQ, copies: copies))
    }

    @Test func theAimSettlesOnlyOnTwoReadsFromTheSameBar() {
        let lgRead = PressAim(frame: CGRect(x: 4500, y: 0, width: 40, height: 30), onPressDisplay: true)
        let mainRead = PressAim(frame: CGRect(x: 1200, y: 0, width: 40, height: 39), onPressDisplay: false)
        #expect(PressAim.settles(lgRead, lgRead, tolerance: 1, awaitingDisplay: true))
        #expect(!PressAim.settles(nil, lgRead, tolerance: 1, awaitingDisplay: true))
        // A stand-in missing for a walk mid-swap is no agreement either way.
        #expect(!PressAim.settles(lgRead, mainRead, tolerance: 1, awaitingDisplay: true))
        #expect(!PressAim.settles(mainRead, lgRead, tolerance: 1, awaitingDisplay: true))
        // Two main reads wait for the display's copy while its bar is listed…
        #expect(!PressAim.settles(mainRead, mainRead, tolerance: 1, awaitingDisplay: true))
        // …and settle when it is not, or no display was asked for.
        #expect(PressAim.settles(mainRead, mainRead, tolerance: 1, awaitingDisplay: false))
        // Still sliding in.
        let moved = PressAim(frame: lgRead.frame.offsetBy(dx: 6, dy: 0), onPressDisplay: true)
        #expect(!PressAim.settles(lgRead, moved, tolerance: 1, awaitingDisplay: true))
    }
}
