import Foundation

/// Journal is the chronological trade log for a profile (not a DB table mirror).
nonisolated struct Journal: Hashable, Codable, Sendable, Identifiable {
    var id: JournalID
    var ownerProfileID: ProfileID
    var title: String
}

nonisolated struct JournalDay: Hashable, Codable, Sendable, Identifiable {
    var id: String { dayKey }
    var dayKey: String
    var date: Date
    var tradeIDs: [TradeID]
    var realizedPnL: Money
    var tradeCount: Int
    var note: String?
}
