import Foundation
import Observation

/// Session cache for `account_payout_cycles` — drives Dashboard prop-firm cycle boundaries.
@Observable
@MainActor
final class SessionPayoutCyclesStore {
    static let shared = SessionPayoutCyclesStore()

    private var cyclesByAccount: [ProfileID: [TradingAccountID: [AccountPayoutCycle]]] = [:]
    private var inFlight: [String: Task<[AccountPayoutCycle], Error>] = [:]

    private init() {}

    func cached(for accountID: TradingAccountID, profileID: ProfileID) -> [AccountPayoutCycle]? {
        cyclesByAccount[profileID]?[accountID]
    }

    func seed(_ cycles: [AccountPayoutCycle], for accountID: TradingAccountID, profileID: ProfileID) {
        var byAccount = cyclesByAccount[profileID, default: [:]]
        byAccount[accountID] = cycles
        cyclesByAccount[profileID] = byAccount
    }

    func invalidate(accountID: TradingAccountID? = nil, profileID: ProfileID? = nil) {
        if let profileID {
            if let accountID {
                cyclesByAccount[profileID]?[accountID] = nil
            } else {
                cyclesByAccount[profileID] = nil
            }
        } else {
            cyclesByAccount = [:]
        }
        if let accountID, let profileID {
            inFlight[flightKey(profileID: profileID, accountID: accountID)]?.cancel()
            inFlight[flightKey(profileID: profileID, accountID: accountID)] = nil
        } else {
            inFlight.values.forEach { $0.cancel() }
            inFlight = [:]
        }
    }

    func invalidateAll() {
        invalidate(accountID: nil, profileID: nil)
    }

    /// Cache-first payout cycle history — one in-flight request per account.
    func cycles(
        for accountID: TradingAccountID,
        profileID: ProfileID,
        repository: any TradeRepository,
        forceNetwork: Bool = false
    ) async throws -> [AccountPayoutCycle] {
        let key = flightKey(profileID: profileID, accountID: accountID)
        if !forceNetwork, let cached = cached(for: accountID, profileID: profileID) {
            SessionNetworkProbe.record(.cacheHit, resource: "payoutCycles", detail: accountID.rawValue)
            return cached
        }
        if let existing = inFlight[key] {
            return try await existing.value
        }
        let task = Task { [repository] in
            SessionNetworkProbe.record(.cacheMiss, resource: "payoutCycles", detail: accountID.rawValue)
            return try await repository.payoutCycleHistory(for: accountID)
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let loaded = try await task.value
        seed(loaded, for: accountID, profileID: profileID)
        return loaded
    }

    private func flightKey(profileID: ProfileID, accountID: TradingAccountID) -> String {
        "\(profileID.rawValue):\(accountID.rawValue)"
    }
}
