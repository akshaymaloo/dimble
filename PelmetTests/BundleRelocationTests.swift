// BundleRelocationTests.swift
// Which bundle names Sparkle can leave behind get renamed to Dimble.app, and
// where: the same folder, whatever it is.

import Foundation
import Testing
@testable import Pelmet

struct BundleRelocationTests {
    @Test func plissPelmetAndNookBundlesMoveToDimbleBesideThemselves() {
        #expect(
            BundleRelocation.relocationTarget(for: URL(fileURLWithPath: "/Applications/Pliss.app"))
                == URL(fileURLWithPath: "/Applications/Dimble.app"))
        #expect(
            BundleRelocation.relocationTarget(for: URL(fileURLWithPath: "/Applications/Pelmet.app"))
                == URL(fileURLWithPath: "/Applications/Dimble.app"))
        #expect(
            BundleRelocation.relocationTarget(for: URL(fileURLWithPath: "/Users/me/Apps/Nook.app"))
                == URL(fileURLWithPath: "/Users/me/Apps/Dimble.app"))
    }

    @Test func aBundleAlreadyNamedDimbleOrAnythingElseStays() {
        #expect(BundleRelocation.relocationTarget(for: URL(fileURLWithPath: "/Applications/Dimble.app")) == nil)
        #expect(BundleRelocation.relocationTarget(for: URL(fileURLWithPath: "/tmp/Pelmet-test.app")) == nil)
        #expect(BundleRelocation.relocationTarget(for: URL(fileURLWithPath: "/tmp/Build/Pelmet")) == nil)
    }
}
