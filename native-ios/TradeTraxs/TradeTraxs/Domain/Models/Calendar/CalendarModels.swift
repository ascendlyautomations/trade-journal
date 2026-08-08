import Foundation

nonisolated enum CalendarEventKind: String, Hashable, Codable, Sendable {
    case tradingDay
    case economic
    case personalReminder
    case report
}

nonisolated struct CalendarEvent: Hashable, Codable, Sendable, Identifiable {
    var id: CalendarEventID
    var ownerProfileID: ProfileID?
    var kind: CalendarEventKind
    var title: String
    var day: Date
    var tradeIDs: [TradeID]
    var realizedPnL: Money?
    var note: String?
}
