// BundlelessMark.swift
// When a live reading of a bar item's host flips its app's sticky
// "bundle-less host" mark (AppState.bundlelessHosts). A host with no
// LaunchServices bundle (ChatGPT Classic's helper) can't be named by the
// assertion's allowlist, so the editor shows its icon inactive and offers a
// launcher.
//
// One reading is not evidence on its own: a walk that lands mid-relaunch
// finds a pid LaunchServices has no record of yet and reads a normal app as
// bundle-less (Sconce and a Pelmet launcher, 2026-09-14; the read cleared
// 75ms later). So a mark flips after `confirmations` readings in a row. But
// once Pelmet conceals, a bundle-less host's icon is never on the bar again,
// and a launch gets one live reading at most, the walk before the first
// converge: the mark never landed (#103). A host that has run for
// `settledHostAge` is no relaunch, so one reading of it marks. Unmarking
// always takes the full run.

import Foundation

public enum BundlelessMark {
    /// Readings in a row that disagree with the mark before it flips.
    public static let confirmations = 3
    /// A bundle-less host older than this marks on one reading: a relaunch
    /// reads that way for ~75ms after the process starts.
    public static let settledHostAge: TimeInterval = 5

    /// One live reading of a bundle's host, against its mark.
    /// - marked: the bundle is marked bundle-less now.
    /// - bundleless: this reading says its host is.
    /// - streak: disagreeing readings in a row before this one.
    /// - hostAge: how long the bundle-less host has run; nil when unknown.
    /// - Returns: whether the mark flips, and the streak to keep (0 once it
    ///   flips, or when the reading agrees with the mark).
    public static func step(
        marked: Bool, bundleless: Bool, streak: Int, hostAge: TimeInterval?
    ) -> (flips: Bool, streak: Int) {
        guard bundleless != marked else { return (false, 0) }
        let streak = streak + 1
        if streak >= confirmations { return (true, 0) }
        if bundleless, let hostAge, hostAge >= settledHostAge { return (true, 0) }
        return (false, streak)
    }
}
