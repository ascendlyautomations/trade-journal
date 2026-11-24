import Foundation
import Observation

/// Session-scoped Trade Rooms home bootstrap, viewer + scope + category keyed, survives tab switches.
@Observable
@MainActor
final class SessionTradeRoomsDiscoveryStore {
    static let shared = SessionTradeRoomsDiscoveryStore()

    private struct Entry {
        var bootstrap: TradeRoomsHomeBootstrap
        var loadedAt: Date
    }

    private var entries: [ProfileID: [String: Entry]] = [:]
    private var inFlight: [String: Task<TradeRoomsHomeBootstrap, Error>] = [:]
    private let freshTTL: TimeInterval = 5 * 60

    private init() {}

    private func cacheKey(scope: TradeRoomDiscoveryScope, category: TradeRoomCategory?) -> String {
        "\(scope.rawValue)|\(category?.rawValue ?? "")"
    }

    private func inFlightKey(viewerID: ProfileID, scope: TradeRoomDiscoveryScope, category: TradeRoomCategory?) -> String {
        "\(viewerID.rawValue):\(cacheKey(scope: scope, category: category))"
    }

    func cached(
        for viewerID: ProfileID,
        scope: TradeRoomDiscoveryScope,
        category: TradeRoomCategory?,
        now: Date = Date()
    ) -> TradeRoomsHomeBootstrap? {
        let key = cacheKey(scope: scope, category: category)
        guard let entry = entries[viewerID]?[key],
              now.timeIntervalSince(entry.loadedAt) < freshTTL
        else { return nil }
        return entry.bootstrap
    }

    func seed(
        _ bootstrap: TradeRoomsHomeBootstrap,
        for viewerID: ProfileID,
        category: TradeRoomCategory?
    ) {
        let key = cacheKey(scope: bootstrap.scope, category: category)
        var scoped = entries[viewerID] ?? [:]
        scoped[key] = Entry(bootstrap: bootstrap, loadedAt: Date())
        entries[viewerID] = scoped
    }

    func coalesce(
        viewerID: ProfileID,
        scope: TradeRoomDiscoveryScope,
        category: TradeRoomCategory?,
        forceNetwork: Bool,
        fetch: @escaping () async throws -> TradeRoomsHomeBootstrap
    ) async throws -> TradeRoomsHomeBootstrap {
        if !forceNetwork, let cached = cached(for: viewerID, scope: scope, category: category) {
            return cached
        }

        let key = inFlightKey(viewerID: viewerID, scope: scope, category: category)
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task { try await fetch() }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let bootstrap = try await task.value
        seed(bootstrap, for: viewerID, category: category)
        return bootstrap
    }

    func invalidate(viewerID: ProfileID? = nil) {
        if let viewerID {
            entries[viewerID] = nil
            let prefix = "\(viewerID.rawValue):"
            inFlight.keys.filter { $0.hasPrefix(prefix) }.forEach { inFlight[$0]?.cancel(); inFlight[$0] = nil }
        } else {
            entries = [:]
            inFlight.values.forEach { $0.cancel() }
            inFlight = [:]
        }
    }
}