import Foundation
import Observation

/// Provenance for cached owner account rows — partial summaries must never satisfy Manage Accounts.
enum OwnerAccountsSnapshotKind: Equatable, Sendable {
    /// Full `ACCOUNTS_SELECT` (+ native insight columns) from REST.
    case rest
    /// Dashboard bootstrap RPC — ACCOUNTS_SELECT-shaped but may omit insight-only columns.
    case dashboard
}

/// Authoritative session account list — single-flight coalescing across Dashboard / Calendar / Trades / Settings.
@Observable
@MainActor
final class SessionAccountsStore {
    static let shared = SessionAccountsStore()

    private var accountsByProfile: [ProfileID: [TradingAccount]] = [:]
    private var snapshotKindByProfile: [ProfileID: OwnerAccountsSnapshotKind] = [:]
    private var inFlight: [ProfileID: Task<[TradingAccount], Error>] = [:]
    private var loadedAt: [ProfileID: Date] = [:]

    /// Account metadata changes rarely — treat as fresh for the session unless invalidated.
    private let freshTTL: TimeInterval = 15 * 60

    private init() {}

    func cached(for profileID: ProfileID) -> [TradingAccount]? {
        accountsByProfile[profileID]
    }

    func snapshotKind(for profileID: ProfileID) -> OwnerAccountsSnapshotKind? {
        snapshotKindByProfile[profileID]
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
        forceNetwork: Bool = false,
        requiresFullOwnerSnapshot: Bool = false,
        viewerProfileID: ProfileID? = nil
    ) async throws -> [TradingAccount] {
        if let viewerProfileID, viewerProfileID != profileID {
            SessionNetworkProbe.record(.cacheMiss, resource: "accounts.denied", detail: profileID.rawValue)
            return []
        }

        if !forceNetwork,
           let cached = accountsByProfile[profileID],
           isFresh(for: profileID),
           cacheSatisfiesRequest(
               kind: snapshotKindByProfile[profileID],
               requiresFullOwnerSnapshot: requiresFullOwnerSnapshot
           )
        {
            SessionNetworkProbe.record(.cacheHit, resource: "accounts", detail: profileID.rawValue)
            return cached
        }

        if !forceNetwork,
           let seeded = detailCache?.accounts(for: profileID),
           !seeded.isEmpty,
           !TradingAccountOwnerDiagnostics.looksLikeSessionSummaryStub(seeded)
        {
            seed(
                seeded,
                for: profileID,
                detailCache: detailCache,
                kind: snapshotKindByProfile[profileID] ?? .rest
            )
            if cacheSatisfiesRequest(
                kind: snapshotKindByProfile[profileID],
                requiresFullOwnerSnapshot: requiresFullOwnerSnapshot
            ) {
                SessionNetworkProbe.record(.cacheHit, resource: "accounts.detailCache", detail: profileID.rawValue)
                return seeded
            }
        }

        if !forceNetwork,
           let disk = SessionDiskCache.loadAccounts(for: profileID),
           !disk.isEmpty,
           !TradingAccountOwnerDiagnostics.looksLikeSessionSummaryStub(disk)
        {
            seed(disk, for: profileID, detailCache: detailCache, kind: .rest)
            if cacheSatisfiesRequest(
                kind: snapshotKindByProfile[profileID],
                requiresFullOwnerSnapshot: requiresFullOwnerSnapshot
            ) {
                SessionNetworkProbe.record(.cacheHit, resource: "accounts.disk", detail: profileID.rawValue)
                return disk
            }
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
        seed(loaded, for: profileID, detailCache: detailCache, kind: .rest)
        return loaded
    }

    func seed(
        _ accounts: [TradingAccount],
        for profileID: ProfileID,
        detailCache: DetailPresentationCache? = nil,
        kind: OwnerAccountsSnapshotKind? = .rest
    ) {
        let resolvedKind = kind ?? snapshotKindByProfile[profileID] ?? .rest
        let merged = Self.mergeOwnerAccounts(
            existing: accountsByProfile[profileID],
            existingKind: snapshotKindByProfile[profileID],
            incoming: accounts,
            incomingKind: resolvedKind
        )
        accountsByProfile[profileID] = merged
        snapshotKindByProfile[profileID] = Self.preferredKind(
            existing: snapshotKindByProfile[profileID],
            incoming: resolvedKind
        )
        loadedAt[profileID] = Date()
        detailCache?.seed(accounts: merged, for: profileID)
        SessionDiskCache.saveAccounts(merged, for: profileID)
        TradingAccountOwnerDiagnostics.logLoadSummary(
            accounts: merged,
            source: diagnosticsSource(for: resolvedKind)
        )
    }

    func invalidate(profileID: ProfileID? = nil) {
        if let profileID {
            accountsByProfile[profileID] = nil
            snapshotKindByProfile[profileID] = nil
            loadedAt[profileID] = nil
            inFlight[profileID]?.cancel()
            inFlight[profileID] = nil
            SessionNetworkProbe.record(.cacheInvalidated, resource: "accounts", detail: profileID.rawValue)
        } else {
            accountsByProfile = [:]
            snapshotKindByProfile = [:]
            loadedAt = [:]
            inFlight.values.forEach { $0.cancel() }
            inFlight = [:]
            SessionNetworkProbe.record(.cacheInvalidated, resource: "accounts", detail: "all")
        }
    }

    // MARK: - Private

    private func cacheSatisfiesRequest(
        kind: OwnerAccountsSnapshotKind?,
        requiresFullOwnerSnapshot: Bool
    ) -> Bool {
        guard let kind else { return false }
        if requiresFullOwnerSnapshot {
            return kind == .rest
        }
        return kind == .rest || kind == .dashboard
    }

    private static func preferredKind(
        existing: OwnerAccountsSnapshotKind?,
        incoming: OwnerAccountsSnapshotKind
    ) -> OwnerAccountsSnapshotKind {
        switch (existing, incoming) {
        case (.rest, _), (_, .rest):
            return .rest
        case (.dashboard, .dashboard), (_, .dashboard):
            return .dashboard
        case (nil, let incoming):
            return incoming
        }
    }

    private static func mergeOwnerAccounts(
        existing: [TradingAccount]?,
        existingKind: OwnerAccountsSnapshotKind?,
        incoming: [TradingAccount],
        incomingKind: OwnerAccountsSnapshotKind
    ) -> [TradingAccount] {
        guard let existing, !existing.isEmpty else { return incoming }

        switch (existingKind, incomingKind) {
        case (.rest, .dashboard):
            let incomingByID = Dictionary(uniqueKeysWithValues: incoming.map { ($0.id, $0) })
            return existing.map { prior in
                guard let dash = incomingByID[prior.id] else { return prior }
                var merged = prior
                merged.isActive = dash.isActive
                merged.canAddTrades = dash.canAddTrades
                return merged
            }
        case (.dashboard, .rest):
            return incoming
        case (.dashboard, .dashboard):
            let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
            return incoming.map { account in
                guard let prior = existingByID[account.id] else { return account }
                var merged = account
                if merged.accountNumber == nil { merged.accountNumber = prior.accountNumber }
                if merged.size == nil { merged.size = prior.size }
                merged.showInAccountDropdowns = prior.showInAccountDropdowns
                merged.customPublicStatus = prior.customPublicStatus
                if merged.propFirmRules == nil { merged.propFirmRules = prior.propFirmRules }
                return merged
            }
        default:
            return incoming
        }
    }

    private func diagnosticsSource(for kind: OwnerAccountsSnapshotKind) -> TradingAccountOwnerDiagnostics.ClassificationSource {
        switch kind {
        case .rest: return .restSelect
        case .dashboard: return .dashboardRpc
        }
    }
}
