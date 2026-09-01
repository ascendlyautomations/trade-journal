import Foundation
import Observation

/// Session memory for Trades history so push → Detail → Back does not cold-reload.
@Observable
@MainActor
final class TradeHistorySessionStore {
    static let shared = TradeHistorySessionStore()

    struct Snapshot: Sendable {
        var queryKey: String
        var profileID: ProfileID
        var items: [Trade]
        var nextCursor: String?
        var filters: TradeHistoryFilters
        var searchText: String
        var loadedAt: Date
    }

    private var snapshots: [String: Snapshot] = [:]
    private var lastActiveKey: String?

    private init() {}

    static func queryKey(
        profileID: ProfileID,
        filters: TradeHistoryFilters,
        searchText: String
    ) -> String {
        TradeHistoryQuery(filters: filters, searchText: searchText).cacheKey(profileID: profileID)
    }

    func snapshot(forKey key: String) -> Snapshot? {
        snapshots[key]
    }

    func save(_ snapshot: Snapshot) {
        snapshots[snapshot.queryKey] = snapshot
        lastActiveKey = snapshot.queryKey
    }

    /// Restore matching snapshot if present (navigation return).
    func restore(
        profileID: ProfileID,
        filters: TradeHistoryFilters,
        searchText: String
    ) -> Snapshot? {
        let key = Self.queryKey(profileID: profileID, filters: filters, searchText: searchText)
        guard let snap = snapshots[key] else {
            SessionNetworkProbe.record(.cacheMiss, resource: "trades.history", detail: key)
            return nil
        }
        lastActiveKey = key
        SessionNetworkProbe.record(
            .cacheHit,
            resource: "trades.history",
            detail: "count=\(snap.items.count)"
        )
        return snap
    }

    /// Local mutation — upsert into matching pages (create + edit).
    func noteCreated(_ trade: Trade) {
        noteUpserted(trade)
    }

    func noteUpserted(_ trade: Trade) {
        SessionNetworkProbe.record(.localMutation, resource: "trades.history", detail: trade.id.rawValue)
        for key in snapshots.keys {
            guard var snap = snapshots[key] else { continue }
            guard snap.profileID == trade.ownerProfileID else { continue }
            let query = TradeHistoryQuery(filters: snap.filters, searchText: snap.searchText)
            let matches = TradeHistoryLocalMatch.matches(trade, query: query)
            let existed = snap.items.contains(where: { $0.id == trade.id })
            snap.items.removeAll { $0.id == trade.id }
            if matches {
                // Prefer front of list for newest / highest PnL; otherwise keep stable order.
                if snap.filters.sort == .newest || snap.filters.sort == .highestPnL || !existed {
                    snap.items.insert(trade, at: 0)
                } else {
                    snap.items.append(trade)
                }
            }
            snap.loadedAt = Date()
            snapshots[key] = snap
        }
    }

    func noteDeleted(id: TradeID, owner: ProfileID) {
        SessionNetworkProbe.record(.localMutation, resource: "trades.history.remove", detail: id.rawValue)
        for key in snapshots.keys {
            guard var snap = snapshots[key] else { continue }
            guard snap.profileID == owner else { continue }
            let before = snap.items.count
            snap.items.removeAll { $0.id == id }
            guard snap.items.count != before else { continue }
            snap.loadedAt = Date()
            snapshots[key] = snap
        }
    }

    func invalidateLists() {
        snapshots = [:]
        lastActiveKey = nil
        SessionNetworkProbe.record(.cacheInvalidated, resource: "trades.history", detail: "lists")
    }

    func invalidate() {
        invalidateLists()
    }
}
