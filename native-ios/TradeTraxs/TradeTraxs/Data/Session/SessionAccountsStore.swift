import Foundation
import Observation

/// Authoritative session account list — single-flight coalescing across Dashboard / Calendar / Trades / Settings.
@Observable
@MainActor
final class SessionAccountsStore {
    static let shared = SessionAccountsStore()

    private var accountsByProfile: [ProfileID: [TradingAccount]] = [:]
    private var inFlight: [ProfileID: Task<[TradingAccount], Error>] = [:]
    private var loadedAt: [ProfileID: Date] = [:]

    /// Account metadata changes rarely — treat as fresh for the session unless invalidated.
    private let freshTTL: TimeInterval = 15 * 60

    private init() {}

    func cached(for profileID: ProfileID) -> [TradingAccount]? {
        accountsByProfile[profileID]
    }

    func isFresh(for profileID: ProfileID, now: Date = Date()) -> Bool {
        guard let loaded = loadedAt[profileID], accountsByProfile[profileID] != nil else { return false }
        return now.timeIntervalSince(loaded) < freshTTL
    }

    /// Cache-first. Networks only on miss / force. Concurrent callers share one request.
    func accounts(
        for profileID: ProfileID,
        detailCache: DetailPresentationCache? = nil,
        repository: any TradeRepository,
        forceNetwork: Bool = false
    ) async throws -> [TradingAccount] {
        if !forceNetwork, let cached = accountsByProfile[profileID], isFresh(for: profileID) {
            SessionNetworkProbe.record(.cacheHit, resource: "accounts", detail: profileID.rawValue)
            return cached
        }

        if !forceNetwork, let seeded = detailCache?.accounts(for: profileID), !seeded.isEmpty {
            seed(seeded, for: profileID, detailCache: detailCache)
            SessionNetworkProbe.record(.cacheHit, resource: "accounts.detailCache", detail: profileID.rawValue)
            return seeded
        }

        if !forceNetwork, let disk = SessionDiskCache.loadAccounts(for: profileID), !disk.isEmpty {
            seed(disk, for: profileID, detailCache: detailCache)
            SessionNetworkProbe.record(.cacheHit, resource: "accounts.disk", detail: profileID.rawValue)
            return disk
        }

        if let existing = inFlight[profileID] {
            SessionNetworkProbe.record(.requestCoalesced, resource: "accounts", detail: profileID.rawValue)
            return try await existing.value
        }

        SessionNetworkProbe.record(
            forceNetwork ? .cacheInvalidated : .cacheMiss,
            resource: "accounts",
            detail: profileID.rawValue
        )
        SessionNetworkProbe.record(.networkFetch, resource: "accounts", detail: profileID.rawValue)

        let task = Task {
            try await repository.accounts(for: profileID)
        }
        inFlight[profileID] = task
        defer { inFlight[profileID] = nil }

        let loaded = try await task.value
        seed(loaded, for: profileID, detailCache: detailCache)
        return loaded
    }

    func seed(
        _ accounts: [TradingAccount],
        for profileID: ProfileID,
        detailCache: DetailPresentationCache? = nil
    ) {
        accountsByProfile[profileID] = accounts
        loadedAt[profileID] = Date()
        detailCache?.seed(accounts: accounts, for: profileID)
        SessionDiskCache.saveAccounts(accounts, for: profileID)
    }

    func invalidate(profileID: ProfileID? = nil) {
        if let profileID {
            accountsByProfile[profileID] = nil
            loadedAt[profileID] = nil
            inFlight[profileID]?.cancel()
            inFlight[profileID] = nil
            SessionNetworkProbe.record(.cacheInvalidated, resource: "accounts", detail: profileID.rawValue)
        } else {
            accountsByProfile = [:]
            loadedAt = [:]
            inFlight.values.forEach { $0.cancel() }
            inFlight = [:]
            SessionNetworkProbe.record(.cacheInvalidated, resource: "accounts", detail: "all")
        }
    }
}
