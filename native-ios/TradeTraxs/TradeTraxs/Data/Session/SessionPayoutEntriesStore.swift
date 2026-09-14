import Foundation
import Observation

/// Session cache for manual `account_payout_entries` — shared across Withdrawals and Manage Accounts.
@Observable
@MainActor
final class SessionPayoutEntriesStore {
    static let shared = SessionPayoutEntriesStore()

    private var entriesByProfile: [ProfileID: [TradingAccountID: [AccountPayoutEntry]]] = [:]

    private init() {}

    func all(for profileID: ProfileID) -> [TradingAccountID: [AccountPayoutEntry]]? {
        entriesByProfile[profileID]
    }

    func seed(_ grouped: [TradingAccountID: [AccountPayoutEntry]], profileID: ProfileID) {
        entriesByProfile[profileID] = grouped
    }

    func setEntries(_ entries: [AccountPayoutEntry], accountID: TradingAccountID, profileID: ProfileID) {
        var grouped = entriesByProfile[profileID, default: [:]]
        grouped[accountID] = entries
        entriesByProfile[profileID] = grouped
    }

    func prepend(_ entry: AccountPayoutEntry, profileID: ProfileID) {
        var grouped = entriesByProfile[profileID, default: [:]]
        var rows = grouped[entry.accountID, default: []]
        guard !rows.contains(where: { $0.id == entry.id }) else { return }
        rows.insert(entry, at: 0)
        grouped[entry.accountID] = rows
        entriesByProfile[profileID] = grouped
    }

    func replace(_ entry: AccountPayoutEntry, profileID: ProfileID) {
        var grouped = entriesByProfile[profileID, default: [:]]
        var rows = grouped[entry.accountID, default: []]
        rows = rows.map { $0.id == entry.id ? entry : $0 }
        grouped[entry.accountID] = rows
        entriesByProfile[profileID] = grouped
    }

    func remove(entryID: AccountPayoutEntryID, accountID: TradingAccountID, profileID: ProfileID) {
        var grouped = entriesByProfile[profileID, default: [:]]
        grouped[accountID] = grouped[accountID, default: []].filter { $0.id != entryID }
        entriesByProfile[profileID] = grouped
    }

    func invalidate(profileID: ProfileID? = nil) {
        if let profileID {
            entriesByProfile[profileID] = nil
        } else {
            entriesByProfile = [:]
        }
    }
}
