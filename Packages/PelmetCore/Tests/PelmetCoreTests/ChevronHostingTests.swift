import CoreGraphics
import Testing
@testable import PelmetCore

@Suite struct ChevronHostingTests {
    // cpierce's MacBook Pro after the lid opened: the built-in alone.
    let builtIn = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let external = CGRect(x: 1728, y: 0, width: 2560, height: 1440)
    var onBuiltInBar: CGRect { CGRect(x: 1437, y: 1117 - 33, width: 36, height: 33) }

    @Test func aChevronOnAnyBarIsHosted() {
        #expect(ChevronHosting.verdict(drawn: onBuiltInBar, screens: [builtIn], walkedItems: 12, walkedChevron: false, recentRehosts: 0) == .hosted)
        let onExternalBar = CGRect(x: 4000, y: 1440 - 24, width: 30, height: 24)
        #expect(ChevronHosting.verdict(drawn: onExternalBar, screens: [builtIn, external], walkedItems: 12, walkedChevron: false, recentRehosts: 0) == .hosted)
    }

    @Test func aWalkedChevronIsHostedWhateverItsWindowSays() {
        // Parked offscreen, or behind a full bar: other paths own those.
        #expect(ChevronHosting.verdict(drawn: nil, screens: [builtIn], walkedItems: 12, walkedChevron: true, recentRehosts: 0) == .hosted)
    }

    @Test func goneFromTheWalkAndEveryBarIsRehosted() {
        // 07:54:38: the walk is back with 12 items, none of them the chevron.
        #expect(ChevronHosting.verdict(drawn: nil, screens: [builtIn], walkedItems: 12, walkedChevron: false, recentRehosts: 0) == .rehost)
        // A window left on the external that went away.
        let onGoneExternal = CGRect(x: 4000, y: 1440 - 24, width: 30, height: 24)
        #expect(ChevronHosting.verdict(drawn: onGoneExternal, screens: [builtIn], walkedItems: 12, walkedChevron: false, recentRehosts: 0) == .rehost)
    }

    @Test func anEmptyWalkIsNoProof() {
        // 07:51:31: the lock screen, the agent's tree has no items.
        guard case .wait = ChevronHosting.verdict(drawn: nil, screens: [builtIn], walkedItems: 0, walkedChevron: false, recentRehosts: 0) else {
            Issue.record("an empty walk must wait")
            return
        }
    }

    @Test func theBudgetStopsRehosting() {
        #expect(ChevronHosting.verdict(drawn: nil, screens: [builtIn], walkedItems: 12, walkedChevron: false, recentRehosts: 1) == .rehost)
        guard case .wait = ChevronHosting.verdict(drawn: nil, screens: [builtIn], walkedItems: 12, walkedChevron: false, recentRehosts: ChevronHosting.budget) else {
            Issue.record("a spent budget must wait")
            return
        }
    }

    @Test func onlyTheTopBandIsTheBar() {
        let midScreen = CGRect(x: 800, y: 500, width: 36, height: 33)
        #expect(!ChevronHosting.isOnABar(midScreen, screens: [builtIn]))
        #expect(!ChevronHosting.isOnABar(.zero, screens: [builtIn]))
        #expect(!ChevronHosting.isOnABar(onBuiltInBar, screens: []))
        #expect(ChevronHosting.isOnABar(onBuiltInBar, screens: [builtIn]))
    }
}
