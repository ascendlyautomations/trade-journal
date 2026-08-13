import Foundation
import Observation

/// Shared month-window trade cache for Calendar + Trading Day (session memory).
@Observable
@MainActor
final class CalendarMonthSessionStore {
    static let shared = CalendarMonthSessionStore()

    private var monthTrades: [String: [Trade]] = [:]
    private var loadedAt: [String: Date] = [:]

    /// Month aggregation is stable for the session unless trades mutate.
    private let freshTTL: TimeInterval = 10 * 60

    private init() {}

    func cacheKey(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    func trades(year: Int, month: Int) -> [Trade]? {
        let key = cacheKey(year: year, month: month)
        guard let trades = monthTrades[key] else { return nil }
        if let loaded = loadedAt[key], Date().timeIntervalSince(loaded) < freshTTL {
            SessionNetworkProbe.record(.cacheHit, resource: "calendar.month", detail: key)
            return trades
        }
        SessionNetworkProbe.record(.cacheStale, resource: "calendar.month", detail: key)
        return trades
    }

    func isFresh(year: Int, month: Int) -> Bool {
        let key = cacheKey(year: year, month: month)
        guard let loaded = loadedAt[key], monthTrades[key] != nil else { return false }
        return Date().timeIntervalSince(loaded) < freshTTL
    }

    func store(_ trades: [Trade], year: Int, month: Int) {
        let key = cacheKey(year: year, month: month)
        monthTrades[key] = trades
        loadedAt[key] = Date()
    }

    func noteCreated(_ trade: Trade) {
        SessionNetworkProbe.record(.localMutation, resource: "calendar.month", detail: trade.id.rawValue)
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month], from: trade.entryAt)
        guard let year = comps.year, let month = comps.month else { return }
        let key = cacheKey(year: year, month: month)
        guard var existing = monthTrades[key] else { return }
        existing.removeAll { $0.id == trade.id }
        existing.append(trade)
        monthTrades[key] = existing
        loadedAt[key] = Date()
    }

    func invalidate(year: Int? = nil, month: Int? = nil) {
        if let year, let month {
            let key = cacheKey(year: year, month: month)
            monthTrades[key] = nil
            loadedAt[key] = nil
            SessionNetworkProbe.record(.cacheInvalidated, resource: "calendar.month", detail: key)
        } else {
            monthTrades = [:]
            loadedAt = [:]
            SessionNetworkProbe.record(.cacheInvalidated, resource: "calendar.month", detail: "all")
        }
    }
}
