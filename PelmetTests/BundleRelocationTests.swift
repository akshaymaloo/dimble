// BundleRelocationTests.swift
// Which bundle names Sparkle can leave behind get renamed to Pliss.app, and
// where: the same folder, whatever it is.

import Foundation
import Testing
@testable import Pelmet

struct BundleRelocationTests {
    @Test func pelmetAndNookBundlesMoveToPlissBesideThemselves() {
        #expect(
            BundleRelocation.relocationTarget(for: URL(fileURLWithPath: "/Applications/Pelmet.app"))
                == URL(fileURLWithPath: "/Applications/Pliss.app"))
        #expect(
            BundleRelocation.relocationTarget(for: URL(fileURLWithPath: "/Users/me/Apps/Nook.app"))
                == URL(fileURLWithPath: "/Users/me/Apps/Pliss.app"))
    }

    @Test func aBundleAlreadyNamedPlissOrAnythingElseStays() {
        #expect(BundleRelocation.relocationTarget(for: URL(fileURLWithPath: "/Applications/Pliss.app")) == nil)
        #expect(BundleRelocation.relocationTarget(for: URL(fileURLWithPath: "/tmp/Pelmet-test.app")) == nil)
        #expect(BundleRelocation.relocationTarget(for: URL(fileURLWithPath: "/tmp/Build/Pelmet")) == nil)
    }
}
