import Foundation
import Testing
@testable import PelmetCore

private let day: TimeInterval = 24 * 3600
private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func item(
    _ id: String,
    _ title: String,
    subtitle: String? = nil,
    keywords: [String] = [],
    alias: String? = nil,
    section: Section? = .visible,
    weight: Double = 1
) -> SearchCandidate {
    SearchCandidate(
        id: id, kind: .item, title: title, subtitle: subtitle,
        keywords: keywords, alias: alias, section: section, weight: weight
    )
}

private func ids(_ matches: [SearchMatch]) -> [String] {
    matches.map(\.candidate.id)
}

@Suite struct FuzzyMatcherTests {
    @Test func tiersAreOrderedExactPrefixWordPrefixAcronymScattered() throws {
        // Same query against five titles built to land in each tier.
        let exact = try #require(FuzzyMatcher.match("cen", in: "Cen"))
        let prefix = try #require(FuzzyMatcher.match("cen", in: "Central Park"))
        let wordPrefix = try #require(FuzzyMatcher.match("cen", in: "Control Center"))
        let acronym = try #require(FuzzyMatcher.match("cce", in: "Control Center Extra"))
        let scattered = try #require(FuzzyMatcher.match("cen", in: "Accessibility Menu"))
        #expect(exact.tier == .exact)
        #expect(prefix.tier == .prefix)
        #expect(wordPrefix.tier == .wordPrefix)
        #expect(acronym.tier == .acronym)
        #expect(scattered.tier == .scattered)
        let scores = [exact, prefix, wordPrefix, acronym, scattered].map(\.score)
        #expect(scores == scores.sorted(by: >))
    }

    @Test func nilWhenLettersAreMissingOrOutOfOrder() {
        #expect(FuzzyMatcher.match("xyz", in: "Control Center") == nil)
        #expect(FuzzyMatcher.match("rc", in: "Cr") == nil)
        #expect(FuzzyMatcher.match("battery", in: "Bat") == nil)
        #expect(FuzzyMatcher.match("", in: "Anything") == nil)
    }

    @Test func exactBeatsFuzzy() throws {
        let exact = try #require(FuzzyMatcher.match("focus", in: "Focus"))
        let fuzzy = try #require(FuzzyMatcher.match("focus", in: "Fox Cabinet Units"))
        #expect(exact.tier == .exact)
        #expect(fuzzy.tier == .scattered)
        #expect(exact.score > fuzzy.score)
    }

    @Test func separatorsDoNotBreakAMatch() throws {
        let wifi = try #require(FuzzyMatcher.match("wifi", in: "Wi-Fi"))
        #expect(wifi.tier == .exact)
        let spaced = try #require(FuzzyMatcher.match("control center", in: "Control Center"))
        #expect(spaced.tier == .exact)
        let squashed = try #require(FuzzyMatcher.match("controlcenter", in: "Control Center"))
        #expect(squashed.tier == .exact)
    }

    @Test func wordStartBeatsMidWord() throws {
        let wordStart = try #require(FuzzyMatcher.match("cen", in: "Control Center"))
        let midWord = try #require(FuzzyMatcher.match("ent", in: "Control Center"))
        #expect(wordStart.score > midWord.score)
        // Same letters, same distance from the front: only the word start differs.
        let atStart = try #require(FuzzyMatcher.match("ab", in: "xx ab"))
        let inside = try #require(FuzzyMatcher.match("ab", in: "xxxab"))
        #expect(atStart.score > inside.score)
    }

    @Test func camelCaseHumpIsAWordStart() throws {
        let hump = try #require(FuzzyMatcher.match("drop", in: "AirDrop"))
        #expect(hump.tier == .wordPrefix)
        #expect(hump.ranges == [3..<7])
        let acronym = try #require(FuzzyMatcher.match("ad", in: "AirDrop"))
        #expect(acronym.tier == .acronym)
    }

    @Test func acronymFindsControlCenter() throws {
        let cc = try #require(FuzzyMatcher.match("cc", in: "Control Center"))
        #expect(cc.tier == .acronym)
        #expect(cc.ranges == [0..<1, 8..<9])
        let ccd = try #require(FuzzyMatcher.match("ccd", in: "Control Center Display"))
        #expect(ccd.tier == .acronym)
        // Skipping a word is fine, reordering is not.
        #expect(FuzzyMatcher.match("cd", in: "Control Center Display")?.tier == .acronym)
        #expect(FuzzyMatcher.match("dc", in: "Control Center Display") == nil)
    }

    @Test func consecutiveRunsBeatScatteredLetters() throws {
        let run = try #require(FuzzyMatcher.match("ener", in: "Generic Network Reader"))
        let spread = try #require(FuzzyMatcher.match("ener", in: "Eager Notes Repeater"))
        #expect(run.tier == .scattered && spread.tier == .scattered)
        #expect(run.ranges == [1..<5])
        #expect(run.score > spread.score)
    }

    @Test func gapsAndLateStartsCost() throws {
        let tight = try #require(FuzzyMatcher.match("trl", in: "Control"))
        let loose = try #require(FuzzyMatcher.match("trl", in: "Tartar Relay Unit Lane"))
        #expect(tight.tier == .scattered)
        let early = try #require(FuzzyMatcher.match("zq", in: "zaq"))
        let late = try #require(FuzzyMatcher.match("zq", in: "aaaaaaaaaazaq"))
        #expect(early.score > late.score)
        #expect(tight.score > 0 && loose.score > 0)
    }

    @Test func mixedPathStillMatches() throws {
        let mixed = try #require(FuzzyMatcher.match("ctrcen", in: "Control Center"))
        #expect(mixed.tier == .scattered)
        #expect(mixed.score > 150)
        #expect(mixed.ranges == [0..<1, 3..<5, 8..<11])
    }

    @Test func diacriticsAndCaseFold() throws {
        let hit = try #require(FuzzyMatcher.match("reglages", in: "Réglages"))
        #expect(hit.tier == .exact)
        #expect(hit.ranges == [0..<8])
        #expect(FuzzyMatcher.match("RÉGLAGES", in: "reglages")?.tier == .exact)
        #expect(FuzzyMatcher.match("uber", in: "Über Eats")?.tier == .prefix)
        #expect(FuzzyMatcher.match("cafe", in: "Café Menu")?.tier == .prefix)
    }

    @Test func rangesAreCharacterOffsetsIntoTheOriginal() throws {
        let hit = try #require(FuzzyMatcher.match("wf", in: "Wi-Fi"))
        #expect(hit.tier == .acronym)
        #expect(hit.ranges == [0..<1, 3..<4])
        let prefix = try #require(FuzzyMatcher.match("wif", in: "Wi-Fi"))
        #expect(prefix.ranges == [0..<2, 3..<4])
    }

    @Test func longInputsFallBackInsteadOfBlowingUp() throws {
        let title = String(repeating: "ab ", count: 100) + "needle"
        let hit = try #require(FuzzyMatcher.match("abbl", in: title))
        #expect(hit.tier == .scattered)
        #expect(hit.score >= FuzzyMatcher.scatteredFloor)
    }
}

@Suite struct SearchHistoryTests {
    @Test func frecencyHalvesEveryTwoWeeks() {
        var history = SearchHistory()
        history.record(id: "a", query: "", at: t0)
        #expect(abs(history.frecency(of: "a", at: t0) - 1) < 1e-9)
        #expect(abs(history.frecency(of: "a", at: t0 + 14 * day) - 0.5) < 1e-9)
        #expect(abs(history.frecency(of: "a", at: t0 + 28 * day) - 0.25) < 1e-9)
        #expect(history.frecency(of: "other", at: t0) == 0)
        // Picks add up, newest weighing most.
        history.record(id: "a", query: "", at: t0 + 14 * day)
        #expect(abs(history.frecency(of: "a", at: t0 + 14 * day) - 1.5) < 1e-9)
        #expect(history.frecencies(at: t0 + 14 * day)["a"] == history.frecency(of: "a", at: t0 + 14 * day))
    }

    @Test func aFuturePickCountsAsJustMade() {
        var history = SearchHistory()
        history.record(id: "a", query: "", at: t0 + day)
        #expect(history.frecency(of: "a", at: t0) == 1)
    }

    @Test func capKeepsTheNewestPicks() {
        var history = SearchHistory()
        for i in 0..<(SearchHistory.maxPicks + 25) {
            history.record(id: "id\(i)", query: "", at: t0 + Double(i))
        }
        #expect(history.picks.count == SearchHistory.maxPicks)
        #expect(history.picks.first?.id == "id25")
        #expect(history.picks.last?.id == "id\(SearchHistory.maxPicks + 24)")
    }

    @Test func latchNeedsTwoPicksOfTheSameRow() {
        var history = SearchHistory()
        history.record(id: "bt", query: "b", at: t0)
        #expect(history.latchedID(for: "b") == nil)
        history.record(id: "bt", query: "B", at: t0 + 60)
        #expect(history.latchedID(for: "b") == "bt")
        #expect(history.latchedID(for: " B ") == "bt")
        #expect(history.latchedID(for: "bl") == nil)
        #expect(history.latchedID(for: "") == nil)
    }

    @Test func aDifferentPickBreaksTheLatchAndTwoMoreHandItOver() {
        var history = SearchHistory()
        history.record(id: "bt", query: "b", at: t0)
        history.record(id: "bt", query: "b", at: t0 + 1)
        history.record(id: "battery", query: "b", at: t0 + 2)
        #expect(history.latchedID(for: "b") == nil)
        history.record(id: "battery", query: "b", at: t0 + 3)
        #expect(history.latchedID(for: "b") == "battery")
        // Picks for other queries don't interfere.
        history.record(id: "bt", query: "bl", at: t0 + 4)
        #expect(history.latchedID(for: "b") == "battery")
    }

    @Test func resetForgetsEverything() {
        var history = SearchHistory()
        history.record(id: "a", query: "a", at: t0)
        history.record(id: "a", query: "a", at: t0 + 1)
        history.reset()
        #expect(history.picks.isEmpty)
        #expect(history.frecency(of: "a", at: t0) == 0)
        #expect(history.latchedID(for: "a") == nil)
    }

    @Test func forgetDropsOneRowAndItsLatch() {
        var history = SearchHistory()
        history.record(id: "a", query: "x", at: t0)
        history.record(id: "a", query: "x", at: t0 + 1)
        history.record(id: "b", query: "y", at: t0 + 2)
        #expect(history.hasPicks(for: "a"))
        history.forget(id: "a")
        #expect(!history.hasPicks(for: "a"))
        #expect(history.hasPicks(for: "b"))
        #expect(history.latchedID(for: "x") == nil)
        #expect(history.frecency(of: "a", at: t0 + 3) == 0)
    }

    @Test func roundTripsThroughJSON() throws {
        var history = SearchHistory()
        history.record(id: "a", query: "Wi-Fi", at: t0)
        let data = try JSONEncoder().encode(history)
        #expect(try JSONDecoder().decode(SearchHistory.self, from: data) == history)
    }
}

@Suite struct SearchRankerTests {
    private let bar: [SearchCandidate] = [
        item("battery", "Battery", keywords: ["batt", "power"]),
        item("bluetooth", "Bluetooth", keywords: ["bt"]),
        item("cc", "Control Center", keywords: ["cc"]),
        item("wifi", "Wi-Fi", keywords: ["wifi", "wlan", "wireless", "network"]),
        item("dropbox", "Dropbox", subtitle: "Dropbox, Inc."),
    ]

    @Test func exactBeatsFuzzyInTheList() {
        let candidates = [
            item("fuzzy", "Fox Cabinet Units"),
            item("exact", "Focus"),
            item("prefix", "Focus Timer"),
        ]
        let result = SearchRanker.rank(query: "focus", candidates: candidates, now: t0)
        #expect(ids(result) == ["exact", "prefix", "fuzzy"])
    }

    @Test func wordStartBeatsMidWordInTheList() {
        let result = SearchRanker.rank(query: "ent", candidates: [
            item("mid", "Control Center"),
            item("start", "Safe Enterprise"),
        ], now: t0)
        #expect(ids(result) == ["start", "mid"])
    }

    @Test func ccFindsControlCenterByAcronym() {
        let result = SearchRanker.rank(query: "cc", candidates: [
            item("cc", "Control Center"),
            item("x", "Accessibility Shortcuts"),
        ], now: t0)
        #expect(result.first?.candidate.id == "cc")
        #expect(result.first?.field == .title)
        #expect(result.first?.titleRanges == [0..<1, 8..<9])
    }

    @Test func btFindsBluetoothByKeywordAndSaysSo() throws {
        let result = SearchRanker.rank(query: "bt", candidates: bar, now: t0)
        let top = try #require(result.first)
        #expect(top.candidate.id == "bluetooth")
        #expect(top.field == .keyword)
        #expect(top.matchedText == "bt")
        #expect(top.titleRanges.isEmpty)
    }

    @Test func reglagesMatchesReglagesWithAccents() throws {
        let result = SearchRanker.rank(query: "reglages", candidates: [
            item("settings", "Réglages"),
            item("other", "Regular Gages"),
        ], now: t0)
        #expect(result.first?.candidate.id == "settings")
        #expect(result.first?.titleRanges == [0..<8])
    }

    @Test func aliasOutranksAnEqualTitle() throws {
        let result = SearchRanker.rank(query: "mail", candidates: [
            item("mail", "Mail"),
            item("slack", "Slack", alias: "mail"),
        ], now: t0)
        #expect(ids(result) == ["slack", "mail"])
        #expect(result.first?.field == .alias)
        #expect(result.first?.matchedText == "mail")
    }

    @Test func withAliasMakesTheRowFindableByIt() throws {
        let base = item("wifi", "Wi-Fi", subtitle: "Control Center", keywords: ["wireless"], section: .hidden, weight: 0.9)
        let named = base.withAlias("home")
        #expect(named.alias == "home")
        #expect(named.title == base.title && named.keywords == base.keywords && named.section == base.section)
        #expect(named.weight == base.weight)
        #expect(SearchRanker.rank(query: "home", candidates: [base], now: t0).isEmpty)
        #expect(ids(SearchRanker.rank(query: "home", candidates: [named], now: t0)) == ["wifi"])
        #expect(named.withAlias(nil).alias == nil)
    }

    @Test func subtitleMatchesRankBelowTitles() {
        let result = SearchRanker.rank(query: "dropbox", candidates: [
            item("sync", "Sync Helper", subtitle: "Dropbox"),
            item("title", "Dropbox"),
        ], now: t0)
        #expect(ids(result) == ["title", "sync"])
        #expect(result.last?.field == .subtitle)
    }

    @Test func hiddenBeatsVisibleOnAnEqualMatch() {
        let candidates = [
            item("visible", "Weather", section: .visible),
            item("hidden", "Weather", section: .hidden),
            item("always", "Weather", section: .alwaysHidden),
        ]
        let result = SearchRanker.rank(query: "weather", candidates: candidates, now: t0)
        #expect(ids(result) == ["hidden", "always", "visible"])
    }

    @Test func rowsWithoutASectionRankLikeVisibleOnes() {
        let result = SearchRanker.rank(query: "quit", candidates: [
            SearchCandidate(id: "command:quit", kind: .command, title: "Quit"),
            item("visible", "Quit", section: .visible),
        ], now: t0)
        #expect(ids(result) == ["command:quit", "visible"])
        #expect(result[0].score == result[1].score)
    }

    @Test func weightScalesTheScore() {
        let result = SearchRanker.rank(query: "dark", candidates: [
            item("setting:dark", "Dark mode", weight: 0.5),
            item("item:dark", "Dark Sky"),
        ], now: t0)
        #expect(ids(result) == ["item:dark", "setting:dark"])
    }

    @Test func tiesKeepCandidateOrder() {
        let candidates = (0..<6).map { item("id\($0)", "Same Title") }
        let result = SearchRanker.rank(query: "same", candidates: candidates, now: t0)
        #expect(ids(result) == (0..<6).map { "id\($0)" })
    }

    @Test func limitTruncatesAfterRanking() {
        let candidates = (0..<10).map { item("id\($0)", "Item \($0)") }
        #expect(SearchRanker.rank(query: "item", candidates: candidates, now: t0, limit: 3).count == 3)
        #expect(SearchRanker.rank(query: "item", candidates: candidates, now: t0, limit: 0).isEmpty)
    }

    @Test func emptyOrSeparatorOnlyQueryFindsNothing() {
        #expect(SearchRanker.rank(query: "", candidates: bar, now: t0).isEmpty)
        #expect(SearchRanker.rank(query: "  - ", candidates: bar, now: t0).isEmpty)
    }

    @Test func frecencyBreaksTiesAndDecaysWithTime() {
        let candidates = [item("a", "Weather"), item("b", "Weather")]
        var history = SearchHistory()
        history.record(id: "b", query: "", at: t0)

        let fresh = SearchRanker.rank(query: "weather", candidates: candidates, history: history, now: t0)
        #expect(ids(fresh) == ["b", "a"])
        let freshBoost = fresh[0].score / fresh[1].score

        let later = SearchRanker.rank(query: "weather", candidates: candidates, history: history, now: t0 + 28 * day)
        let laterBoost = later[0].score / later[1].score
        #expect(freshBoost > 1)
        #expect(laterBoost > 1)
        #expect(laterBoost < freshBoost)

        let forgotten = SearchRanker.rank(query: "weather", candidates: candidates, history: history, now: t0 + 365 * day)
        // A year on, the pick is a rounding error; candidate order wins again.
        #expect(forgotten[0].score / forgotten[1].score < 1.0001)
    }

    @Test func frecencyNeverOutweighsAnExactTitleOverAScatteredOne() {
        var history = SearchHistory()
        for i in 0..<50 { history.record(id: "habit", query: "", at: t0 + Double(i)) }
        let result = SearchRanker.rank(query: "focus", candidates: [
            item("habit", "Fox Cabinet Units", section: .hidden),
            item("exact", "Focus"),
        ], history: history, now: t0 + 50)
        #expect(result.first?.candidate.id == "exact")
    }

    @Test func latchPutsTheRepeatedPickFirst() {
        let candidates = [
            item("battery", "Battery"),
            item("bluetooth", "Bluetooth"),
            item("b", "B"),
        ]
        var history = SearchHistory()
        #expect(ids(SearchRanker.rank(query: "b", candidates: candidates, history: history, now: t0)).first == "b")

        history.record(id: "battery", query: "b", at: t0)
        history.record(id: "battery", query: "b", at: t0 + 10)
        let latched = SearchRanker.rank(query: "b", candidates: candidates, history: history, now: t0 + 20)
        #expect(latched.first?.candidate.id == "battery")

        // A different pick for the same query ends the latch.
        history.record(id: "bluetooth", query: "b", at: t0 + 30)
        let broken = SearchRanker.rank(query: "b", candidates: candidates, history: history, now: t0 + 40)
        #expect(broken.first?.candidate.id == "b")
    }

    @Test func latchOnlyAppliesToTheSameQuery() {
        let candidates = [item("battery", "Battery"), item("bluetooth", "Bluetooth")]
        var history = SearchHistory()
        history.record(id: "battery", query: "b", at: t0)
        history.record(id: "battery", query: "b", at: t0 + 1)
        let other = SearchRanker.rank(query: "bl", candidates: candidates, history: history, now: t0 + 2)
        #expect(other.first?.candidate.id == "bluetooth")
    }

    @Test func restStateListsConcealedItemsByFrecencyThenOrder() {
        let candidates = [
            item("visible", "Clock", section: .visible),
            item("h1", "Alpha", section: .hidden),
            item("h2", "Beta", section: .alwaysHidden),
            item("h3", "Gamma", section: .hidden),
            item("setting", "Dark mode", section: nil),
            SearchCandidate(id: "launcher:x", kind: .launcher, title: "Launcher", section: .hidden),
            item("h4", "Delta", section: .alwaysHidden),
        ]
        var history = SearchHistory()
        history.record(id: "h3", query: "", at: t0 - 20 * day)
        history.record(id: "h4", query: "", at: t0 - 1 * day)
        history.record(id: "visible", query: "", at: t0)

        let rest = SearchRanker.restState(candidates: candidates, history: history, now: t0)
        #expect(ids(rest) == ["h4", "h3", "h1", "h2"])
        #expect(rest[0].score > rest[1].score)
        #expect(rest[2].score == 0)

        #expect(ids(SearchRanker.restState(candidates: candidates, history: history, now: t0, limit: 2)) == ["h4", "h3"])
        #expect(SearchRanker.restState(candidates: candidates, now: t0).count == 4)
        let many = (0..<9).map { item("h\($0)", "H\($0)", section: .hidden) }
        #expect(SearchRanker.restState(candidates: many, now: t0).count == 5)
    }

    @Test func completionKeepsTheTitlesCasing() throws {
        let dropbox = item("dropbox", "Dropbox")
        let result = SearchRanker.rank(query: "dr", candidates: [dropbox], now: t0)
        let match = try #require(result.first)
        #expect(SearchRanker.completion(query: "dr", for: match) == "opbox")
        #expect(SearchRanker.completion(query: "DR", for: match) == "opbox")
        // The whole title typed: nothing left to complete.
        #expect(SearchRanker.completion(query: "dropbox", for: match) == nil)
        #expect(SearchRanker.completion(query: "", for: match) == nil)
    }

    @Test func completionIgnoresDiacriticsAndKeepsSeparators() throws {
        let regl = item("settings", "Réglages Système")
        let match = try #require(SearchRanker.rank(query: "reg", candidates: [regl], now: t0).first)
        #expect(SearchRanker.completion(query: "reg", for: match) == "lages Système")
        let wifi = item("wifi", "Wi-Fi")
        let wifiMatch = try #require(SearchRanker.rank(query: "wi-", candidates: [wifi], now: t0).first)
        #expect(SearchRanker.completion(query: "wi-", for: wifiMatch) == "Fi")
    }

    @Test func acronymAndKeywordHitsDoNotComplete() throws {
        let cc = try #require(SearchRanker.rank(query: "cc", candidates: [item("cc", "Control Center")], now: t0).first)
        #expect(SearchRanker.completion(query: "cc", for: cc) == nil)
        let bt = try #require(SearchRanker.rank(query: "bt", candidates: [item("bt", "Bluetooth", keywords: ["bt"])], now: t0).first)
        #expect(SearchRanker.completion(query: "bt", for: bt) == nil)
        let sub = try #require(SearchRanker.rank(query: "inc", candidates: [item("x", "Sync", subtitle: "Dropbox, Inc.")], now: t0).first)
        #expect(SearchRanker.completion(query: "inc", for: sub) == nil)
    }

    @Test func queryTypedInADifferentCaseRanksTheSame() {
        let lower = SearchRanker.rank(query: "control", candidates: bar, now: t0)
        let upper = SearchRanker.rank(query: "CONTROL", candidates: bar, now: t0)
        #expect(lower == upper)
    }
}

@Suite struct SynonymsTests {
    @Test func tableCoversTheCommonItems() {
        #expect(Synonyms.keywords(title: "Wi-Fi") == ["wifi", "wlan", "wireless", "network"])
        #expect(Synonyms.keywords(title: "Bluetooth") == ["bt"])
        #expect(Synonyms.keywords(title: "Sound").contains("vol"))
        #expect(Synonyms.keywords(title: "Battery").contains("batt"))
        #expect(Synonyms.keywords(title: "Focus").contains("dnd"))
        #expect(Synonyms.keywords(title: "Control Center") == ["cc"])
        #expect(Synonyms.keywords(title: "Now Playing").contains("music"))
        #expect(Synonyms.keywords(title: "Clock").contains("date"))
        #expect(Synonyms.keywords(title: "Screen Mirroring").contains("airplay"))
        #expect(Synonyms.keywords(title: "Time Machine").contains("backup"))
        #expect(Synonyms.keywords(title: "Quick Note").contains("note"))
        #expect(Synonyms.keywords(title: "Notification Center").contains("nc"))
        #expect(Synonyms.keywords(title: "Fast User Switching").contains("account"))
        #expect(Synonyms.keywords(title: "Display").contains("brightness"))
        #expect(Synonyms.keywords(title: "Text Input").contains("kb"))
    }

    @Test func matchesLooselyOnTitleWords() {
        #expect(Synonyms.keywords(title: "WIFI") == Synonyms.keywords(title: "Wi‑Fi"))
        #expect(Synonyms.keywords(title: "Bluetooth Explorer") == ["bt"])
        #expect(Synonyms.keywords(title: "  sound output ").contains("audio"))
    }

    @Test func fallsBackToAppleBundleIDs() {
        #expect(Synonyms.keywords(title: "Item-0", bundleID: "com.apple.menuextra.bluetooth") == ["bt"])
        #expect(Synonyms.keywords(title: "WLAN", bundleID: "com.apple.menuextra.wifi").contains("wifi"))
        // Localized title, Apple bundle.
        #expect(Synonyms.keywords(title: "Batterie", bundleID: "com.apple.menuextra.battery").contains("power"))
        // Third parties keep their own names.
        #expect(Synonyms.keywords(title: "Item-0", bundleID: "com.example.menuextra.bluetooth").isEmpty)
    }

    @Test func unknownItemsGetNothing() {
        #expect(Synonyms.keywords(title: "Dropbox").isEmpty)
        #expect(Synonyms.keywords(title: "", bundleID: nil).isEmpty)
    }

    @Test func synonymsFeedTheRanker() throws {
        let wifi = item("wifi", "Wi-Fi", keywords: Synonyms.keywords(title: "Wi-Fi"))
        let match = try #require(SearchRanker.rank(query: "wireless", candidates: [wifi], now: t0).first)
        #expect(match.field == .keyword)
        #expect(match.matchedText == "wireless")
    }
}

@Suite struct SearchPerformanceTests {
    private static let stems = [
        "Control", "Center", "Display", "Battery", "Weather", "Notes", "Camera", "Mirror", "Sync", "Cloud",
        "Drive", "Music", "Clock", "Timer", "Focus", "Input", "Network", "Status", "Helper", "Monitor",
    ]

    private func corpus(title: (Int) -> String) -> [SearchCandidate] {
        (0..<200).map { i in
            item(
                "item\(i)", title(i),
                subtitle: Self.stems[(i * 3) % Self.stems.count] + " Inc.",
                keywords: i % 4 == 0 ? ["alias\(i)", "kw"] : [],
                section: [.visible, .hidden, .alwaysHidden][i % 3]
            )
        }
    }

    /// Mean time of one `rank` call over a few dozen runs.
    private func perCall(query: String, candidates: [SearchCandidate], hits: inout Int) -> Duration {
        var history = SearchHistory()
        for i in 0..<120 { history.record(id: "item\(i % 50)", query: "cont", at: t0 + Double(i * 600)) }
        let clock = ContinuousClock()
        let runs = 50
        var total = Duration.zero
        for _ in 0..<runs {
            total += clock.measure {
                hits = SearchRanker.rank(
                    query: query, candidates: candidates, history: history, now: t0 + 90_000, limit: 200
                ).count
            }
        }
        return total / runs
    }

    @Test func rankingTwoHundredCandidatesStaysFast() {
        // Debug builds are several times slower; the 2ms budget is a release number.
        #if DEBUG
        let budget = Duration.milliseconds(20)
        #else
        let budget = Duration.milliseconds(2)
        #endif

        // Mixed titles, a selective 6-letter query.
        let mixed = corpus { i in
            "\(Self.stems[i % Self.stems.count]) \(Self.stems[(i * 7 + 3) % Self.stems.count]) \(i)"
        }
        var hits = 0
        let selective = perCall(query: "cntrol", candidates: mixed, hits: &hits)
        print("search perf: 200 mixed candidates, \"cntrol\", \(hits) hits, \(selective) per call")
        #expect(hits > 0)
        #expect(selective < budget)

        // Worst case: every title matches the query as a scattered subsequence,
        // so the DP runs 200 times per call.
        let loose = corpus { i in "Control Center Display Monitor \(i)" }
        let worst = perCall(query: "ctrdis", candidates: loose, hits: &hits)
        print("search perf: 200 all-matching candidates, \"ctrdis\", \(hits) hits, \(worst) per call")
        #expect(hits == 200)
        #expect(worst < budget)
    }
}

