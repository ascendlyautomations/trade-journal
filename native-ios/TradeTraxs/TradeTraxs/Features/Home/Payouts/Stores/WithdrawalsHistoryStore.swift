import Foundation
import Observation

/// Authoritative in-memory withdrawal history — ledger entries + funded prop payout cycles.
@Observable
@MainActor
final class WithdrawalsHistoryStore {
    static let shared = WithdrawalsHistoryStore()

    private(set) var profileID: ProfileID?
    private(set) var ledgerByAccount: [TradingAccountID: [AccountPayoutEntry]] = [:]
    private(set) var cyclesByAccount: [TradingAccountID: [AccountPayoutCycle]] = [:]

    private init() {}

    var isEmpty: Bool {
        ledgerByAccount.values.allSatisfy(\.isEmpty) && cyclesByAccount.values.allSatisfy(\.isEmpty)
    }

    func bindProfile(_ profileID: ProfileID) {
        self.profileID = profileID
    }

    func hydrateFromSessionCaches(profileID: ProfileID) {
        self.profileID = profileID
        if let ledger = SessionPayoutEntriesStore.shared.all(for: profileID) {
            ledgerByAccount = ledger
        }
    }

    func hydrateCyclesFromSessionStore(profileID: ProfileID, accountIDs: [TradingAccountID]) {
        self.profileID = profileID
        var grouped = cyclesByAccount
        for accountID in accountIDs {
            if let cached = SessionPayoutCyclesStore.shared.cached(for: accountID, profileID: profileID) {
                grouped[accountID] = cached
            }
        }
        cyclesByAccount = grouped
    }

    func applyLedgerSnapshot(
        _ grouped: [TradingAccountID: [AccountPayoutEntry]],
        profileID: ProfileID
    ) {
        self.profileID = profileID
        ledgerByAccount = Self.mergeLedger(local: ledgerByAccount, server: grouped)
        SessionPayoutEntriesStore.shared.seed(ledgerByAccount, profileID: profileID)
    }

    func setLedgerEntries(
        _ entries: [AccountPayoutEntry],
        accountID: TradingAccountID,
        profileID: ProfileID
    ) {
        self.profileID = profileID
        var grouped = ledgerByAccount
        grouped[accountID] = entries
        ledgerByAccount = grouped
        SessionPayoutEntriesStore.shared.setEntries(entries, accountID: accountID, profileID: profileID)
    }

    func prependLedgerEntry(_ entry: AccountPayoutEntry, profileID: ProfileID) {
        self.profileID = profileID
        var grouped = ledgerByAccount
        var rows = grouped[entry.accountID, default: []]
        guard !rows.contains(where: { $0.id == entry.id }) else { return }
        rows.insert(entry, at: 0)
        grouped[entry.accountID] = rows
        ledgerByAccount = grouped
        SessionPayoutEntriesStore.shared.prepend(entry, profileID: profileID)
        WithdrawalsTrace.storeIdentity("prependLedgerEntry")
    }

    func replaceLedgerEntry(_ entry: AccountPayoutEntry, profileID: ProfileID) {
        self.profileID = profileID
        var grouped = ledgerByAccount
        var rows = grouped[entry.accountID, default: []]
        rows = rows.map { $0.id == entry.id ? entry : $0 }
        grouped[entry.accountID] = rows
        ledgerByAccount = grouped
        SessionPayoutEntriesStore.shared.replace(entry, profileID: profileID)
    }

    func removeLedgerEntry(
        entryID: AccountPayoutEntryID,
        accountID: TradingAccountID,
        profileID: ProfileID
    ) {
        self.profileID = profileID
        var grouped = ledgerByAccount
        grouped[accountID] = grouped[accountID, default: []].filter { $0.id != entryID }
        ledgerByAccount = grouped
        SessionPayoutEntriesStore.shared.remove(
            entryID: entryID,
            accountID: accountID,
            profileID: profileID
        )
    }

    func applyCyclesSnapshot(
        _ grouped: [TradingAccountID: [AccountPayoutCycle]],
        profileID: ProfileID
    ) {
        self.profileID = profileID
        cyclesByAccount = Self.mergeCycles(local: cyclesByAccount, server: grouped)
        for (accountID, cycles) in cyclesByAccount {
            SessionPayoutCyclesStore.shared.seed(cycles, for: accountID, profileID: profileID)
        }
    }

    /// Confirmed prop payout — visible immediately without waiting on refetch.
    func prependCompletedPropCycle(_ cycle: AccountPayoutCycle, profileID: ProfileID) {
        self.profileID = profileID
        var grouped = cyclesByAccount
        var rows = grouped[cycle.accountID, default: []]
        if let index = rows.firstIndex(where: { $0.id == cycle.id }) {
            rows[index] = cycle
        } else {
            rows.insert(cycle, at: 0)
        }
        grouped[cycle.accountID] = rows
        cyclesByAccount = grouped
        SessionPayoutCyclesStore.shared.seed(rows, for: cycle.accountID, profileID: profileID)
        WithdrawalsTrace.storeIdentity("prependCompletedPropCycle")
    }

    func ledgerEntryCount() -> Int {
        ledgerByAccount.values.reduce(0) { $0 + $1.count }
    }

    func completedPropCycleCount() -> Int {
        cyclesByAccount.values.reduce(0) { partial, cycles in
            partial + PropFirmPayoutCycleSupport.selectCompletedPayoutHistory(cycles).count
        }
    }

    private static func mergeLedger(
        local: [TradingAccountID: [AccountPayoutEntry]],
        server: [TradingAccountID: [AccountPayoutEntry]]
    ) -> [TradingAccountID: [AccountPayoutEntry]] {
        var merged = server
        let accountIDs = Set(local.keys).union(server.keys)
        for accountID in accountIDs {
            let serverRows = server[accountID] ?? []
            let serverIDs = Set(serverRows.map(\.id))
            let pendingLocal = (local[accountID] ?? []).filter { !serverIDs.contains($0.id) }
            let combined = pendingLocal + serverRows
            merged[accountID] = combined.sorted { lhs, rhs in
                if lhs.payoutDate != rhs.payoutDate {
                    return lhs.payoutDate > rhs.payoutDate
                }
                return lhs.id.rawValue > rhs.id.rawValue
            }
        }
        return merged
    }

    private static func mergeCycles(
        local: [TradingAccountID: [AccountPayoutCycle]],
        server: [TradingAccountID: [AccountPayoutCycle]]
    ) -> [TradingAccountID: [AccountPayoutCycle]] {
        var merged = server
        let accountIDs = Set(local.keys).union(server.keys)
        for accountID in accountIDs {
            let serverRows = server[accountID] ?? []
            let serverIDs = Set(serverRows.map(\.id))
            let pendingLocal = (local[accountID] ?? []).filter { !serverIDs.contains($0.id) }
            merged[accountID] = pendingLocal + serverRows
        }
        return merged
    }

    func invalidate(profileID: ProfileID? = nil) {
        if let profileID, self.profileID == profileID {
            ledgerByAccount = [:]
            cyclesByAccount = [:]
        } else if profileID == nil {
            self.profileID = nil
            ledgerByAccount = [:]
            cyclesByAccount = [:]
        }
    }
}
