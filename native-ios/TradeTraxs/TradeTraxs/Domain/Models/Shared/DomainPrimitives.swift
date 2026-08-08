import Foundation

/// Currency amount using decimal precision — never Double for money.
nonisolated struct Money: Hashable, Codable, Sendable, Comparable {
    var amount: Decimal
    var currencyCode: String

    init(amount: Decimal, currencyCode: String = "USD") {
        self.amount = amount
        self.currencyCode = currencyCode
    }

    static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.amount < rhs.amount
    }
}

nonisolated struct DateIntervalValue: Hashable, Codable, Sendable {
    var start: Date
    var end: Date
}

/// Keyset / cursor page — unbounded list downloads are forbidden by architecture.
nonisolated struct CursorPage<Element: Sendable>: Sendable {
    var items: [Element]
    var nextCursor: String?
    var hasMore: Bool { nextCursor != nil }
}

nonisolated struct PageRequest: Hashable, Codable, Sendable {
    var cursor: String?
    var limit: Int

    init(cursor: String? = nil, limit: Int = 30) {
        self.cursor = cursor
        self.limit = limit
    }
}

nonisolated enum ContentVisibility: String, Hashable, Codable, Sendable {
    case `private`
    case `public`
    case followersOnly
}

nonisolated enum MediaKind: String, Hashable, Codable, Sendable {
    case image
    case video
    case file
}

/// Opaque media reference — not a URLSession concern; Data maps storage keys later.
nonisolated struct MediaReference: Hashable, Codable, Sendable {
    var id: String
    var kind: MediaKind
    var altText: String?
}

nonisolated struct Symbol: Hashable, Codable, Sendable {
    var ticker: String
}
