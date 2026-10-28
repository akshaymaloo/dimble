// HelperProtocol.swift
// The wire between the main app and a section helper (docs/HELPER-PROCESS-
// PLAN.md). A helper hosts NSStatusItems and nothing else: it is told the
// full list to host (idempotent `sync`) and reports what the user did.

import Foundation

/// One status item a helper should host.
public struct HostedItem: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case separator
        case launcher
        case extra
    }

    /// The Pelmet-minted title (`SeparatorSpec.itemTitle` …): identity on
    /// both sides, the AX title, and the autosave name.
    public var title: String
    public var kind: Kind
    /// Button text (separator glyph) — empty for image items.
    public var text: String
    /// Fixed length in points; nil = variable.
    public var length: Double?
    public var alpha: Double
    /// PNG for image items (launcher / extra glyph), nil for text items.
    public var imagePNG: Data?
    public var imageIsTemplate: Bool
    public var removable: Bool

    public init(
        title: String, kind: Kind, text: String = "", length: Double? = nil,
        alpha: Double = 1, imagePNG: Data? = nil, imageIsTemplate: Bool = true,
        removable: Bool = true
    ) {
        self.title = title
        self.kind = kind
        self.text = text
        self.length = length
        self.alpha = alpha
        self.imagePNG = imagePNG
        self.imageIsTemplate = imageIsTemplate
        self.removable = removable
    }
}

/// Main → helper.
public enum HelperCommand: Codable, Sendable {
    /// The complete list; the helper diffs against what it hosts.
    case sync([HostedItem])
    case quit

    public var isValid: Bool {
        switch self {
        case .quit: return true
        case .sync(let items):
            return items.count <= 256 && Set(items.map(\.title)).count == items.count
                && items.allSatisfy {
                    !$0.title.isEmpty && $0.title.utf8.count <= 256 && $0.text.utf8.count <= 1024
                        && $0.alpha.isFinite && (0...1).contains($0.alpha)
                        && ($0.length.map { $0.isFinite && (0...1024).contains($0) } ?? true)
                        && ($0.imagePNG?.count ?? 0) <= 256 * 1024
                }
        }
    }
}

/// Helper → main.
public enum HelperEvent: Codable, Sendable {
    /// The helper is listening and hosting nothing yet.
    case ready(bundle: String)
    /// A hosted item is registered with the bar.
    case hosted(bundle: String, title: String)
    case clicked(bundle: String, title: String, rightButton: Bool, x: Double, y: Double)
    /// The user ⌘-dragged the item off the bar; the helper already unhosted it.
    case draggedOff(bundle: String, title: String)

    public var bundle: String {
        switch self {
        case .ready(let bundle), .hosted(let bundle, _), .clicked(let bundle, _, _, _, _),
             .draggedOff(let bundle, _): return bundle
        }
    }

    public func isAuthorized(peer: String, items: [HostedItem]) -> Bool {
        guard bundle == peer else { return false }
        switch self {
        case .ready: return true
        case .hosted(_, let title): return items.contains { $0.title == title }
        case .clicked(_, let title, _, let x, let y):
            return x.isFinite && y.isFinite && items.contains { $0.title == title }
        case .draggedOff(_, let title):
            return items.contains { $0.title == title && $0.removable }
        }
    }
}

public enum HelperWire {
    public static func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard data.count <= HelperLink.maximumMessageBytes else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
