import Foundation
import Observation

/// Session-scoped Trade Rooms home bootstrap — viewer + scope keyed, survives tab switches.
@Observable
@MainActor
final class SessionTradeRoomsDiscoveryStore {
    static let shared = SessionTradeRoomsDiscoveryStore()

    private struct Entry {
        var bootstrap: TradeRoomsHomeBootstrap
        var loadedAt: Date
    }

    private var entries: [ProfileID: [TradeRoomDiscoveryScope: Entry]] = [:]
    private var inFlight: [String: Task<TradeRoomsHomeBootstrap, Error>] = [:]
    private let freshTTL: TimeInterval = 5 * 60

    private init() {}

    func cached(for viewerID: ProfileID, scope: TradeRoomDiscoveryScope, now: Date = Date()) -> TradeRoomsHomeBootstrap? {
        guard let entry = entries[viewerID]?[scope],
              now.timeIntervalSince(entry.loadedAt) < freshTTL
        else { return nil }
        return entry.bootstrap
    }

    func seed(_ bootstrap: TradeRoomsHomeBootstrap, for viewerID: ProfileID) {
        var scoped = entries[viewerID] ?? [:]
        scoped[bootstrap.scope] = Entry(bootstrap: bootstrap, loadedAt: Date())
        entries[viewerID] = scoped
    }

    func coalesce(
        viewerID: ProfileID,
        scope: TradeRoomDiscoveryScope,
        forceNetwork: Bool,
        fetch: @escaping () async throws -> TradeRoomsHomeBootstrap
    ) async throws -> TradeRoomsHomeBootstrap {
        if !forceNetwork, let cached = cached(for: viewerID, scope: scope) {
            return cached
        }

        let key = "\(viewerID.rawValue):\(scope.rawValue)"
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task { try await fetch() }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let bootstrap = try await task.value
        seed(bootstrap, for: viewerID)
        return bootstrap
    }

    func invalidate(viewerID: ProfileID? = nil) {
        if let viewerID {
            entries[viewerID] = nil
            inFlight.keys.filter { $0.hasPrefix("\(viewerID.rawValue):") }.forEach { inFlight[$0]?.cancel(); inFlight[$0] = nil }
        } else {
            entries = [:]
            inFlight.values.forEach { $0.cancel() }
            inFlight = [:]
        }
    }
}
