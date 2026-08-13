import Foundation
import Observation

/// Session-scoped owner trade list used by Dashboard (and compatible consumers).
///
/// Bounded page only — never a full-table dump. Mutations upsert/remove by ID.
@Observable
@MainActor
final class SessionOwnerTradesStore {
    static let shared = SessionOwnerTradesStore()

    private var tradesByOwner: [ProfileID: [Trade]] = [:]
    private var loadedAt: [ProfileID: Date] = [:]
    private var inFlight: [ProfileID: Task<[Trade], Error>] = [:]

    /// Analytics window — Realtime / local mutations keep this coherent longer.
    private let freshTTL: TimeInterval = 10 * 60

    private init() {}

    func cached(for profileID: ProfileID) -> [Trade]? {
        tradesByOwner[profileID]
    }

    func isFresh(for profileID: ProfileID, now: Date = Date()) -> Bool {
        guard let loaded = loadedAt[profileID], tradesByOwner[profileID] != nil else { return false }
        return now.timeIntervalSince(loaded) < freshTTL
    }

    func trades(
        for profileID: ProfileID,
        detailCache: DetailPresentationCache,
        repository: any TradeRepository,
        limit: Int = 500,
        forceNetwork: Bool = false
    ) async throws -> [Trade] {
        if !forceNetwork, let cached = tradesByOwner[profileID], isFresh(for: profileID) {
            SessionNetworkProbe.record(
                .cacheHit,
                resource: "ownerTrades",
                detail: "count=\(cached.count)"
            )
            return cached
        }

        if let existing = inFlight[profileID] {
            SessionNetworkProbe.record(.requestCoalesced, resource: "ownerTrades", detail: profileID.rawValue)
            return try await existing.value
        }

        SessionNetworkProbe.record(.cacheMiss, resource: "ownerTrades", detail: profileID.rawValue)
        SessionNetworkProbe.record(.networkFetch, resource: "ownerTrades", detail: profileID.rawValue)

        let task = Task {
            try await repository.trades(
                ownedBy: profileID,
                accountID: nil,
                page: PageRequest(limit: limit),
                publicOnly: false
            ).items
        }
        inFlight[profileID] = task
        defer { inFlight[profileID] = nil }

        let loaded = try await task.value
        seed(loaded, for: profileID, detailCache: detailCache)
        return loaded
    }

    func seed(_ trades: [Trade], for profileID: ProfileID, detailCache: DetailPresentationCache) {
        tradesByOwner[profileID] = trades
        loadedAt[profileID] = Date()
        detailCache.seed(trades: trades)
        SessionDiskCache.saveOwnerTrades(trades, for: profileID)
    }

    func upsert(_ trade: Trade, detailCache: DetailPresentationCache) {
        let owner = trade.ownerProfileID
        var list = tradesByOwner[owner] ?? []
        list.removeAll { $0.id == trade.id }
        list.insert(trade, at: 0)
        tradesByOwner[owner] = list
        loadedAt[owner] = Date()
        detailCache.seed(trade)
        SessionDiskCache.saveOwnerTrades(list, for: owner)
        SessionNetworkProbe.record(.localMutation, resource: "ownerTrades", detail: trade.id.rawValue)
    }

    func remove(id: TradeID, owner: ProfileID) {
        guard var list = tradesByOwner[owner] else { return }
        list.removeAll { $0.id == id }
        tradesByOwner[owner] = list
        loadedAt[owner] = Date()
        SessionDiskCache.saveOwnerTrades(list, for: owner)
        SessionNetworkProbe.record(.localMutation, resource: "ownerTrades.remove", detail: id.rawValue)
    }

    func invalidate(profileID: ProfileID? = nil) {
        if let profileID {
            tradesByOwner[profileID] = nil
            loadedAt[profileID] = nil
            inFlight[profileID]?.cancel()
            inFlight[profileID] = nil
        } else {
            inFlight.values.forEach { $0.cancel() }
            tradesByOwner = [:]
            loadedAt = [:]
            inFlight = [:]
        }
        SessionNetworkProbe.record(.cacheInvalidated, resource: "ownerTrades", detail: profileID?.rawValue ?? "all")
    }
}
