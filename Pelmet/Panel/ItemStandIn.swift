// ItemStandIn.swift
// What a tile draws for an item before a picture of it lands, the editor's
// chain (`TileGlyph`): SystemUIServer's pinned pair hands over a blank
// rounded square, so Apple's own mark stands in for it (#19); every other
// item gets its icon.

import AppKit
import PelmetCore

enum ItemStandIn {
    /// Nil when there is no icon to show.
    static func image(for id: ItemID) -> NSImage? {
        if id.bundleID == PelmetBundle.systemUIServerID {
            // Keyed on the enumerator's un-localized title ("Siri, TimeMachine").
            var rawTitle = ""
            if case .status(_, let title) = id.parsed { rawTitle = title }
            return ExtraGlyph.pinnedAppleExtra(rawTitle: rawTitle)
        }
        return ItemImageCache.icon(for: id)
    }
}
