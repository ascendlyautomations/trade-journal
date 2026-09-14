import Foundation
import Observation

/// Broadcasts trading-account mutations so Dashboard / Calendar / Add Trade refresh without polling.
@Observable
@MainActor
final class AccountMutationStore {
    enum MutationKind: Equatable {
        case generic
        case payoutRecorded(TradingAccountID)
    }

    static let shared = AccountMutationStore()

    private(set) var revision: Int = 0
    private(set) var latestAccountID: TradingAccountID?
    private(set) var latestKind: MutationKind = .generic

    private init() {}

    func noteAccountCreated(_ account: TradingAccount, allAccounts: [TradingAccount]) {
        latestKind = .generic
        latestAccountID = account.id
        AccountPersistedCacheCoordinator.noteAccountsUpdated(allAccounts, viewerID: account.ownerProfileID)
        revision += 1
    }

    func noteAccountUpdated(_ account: TradingAccount, allAccounts: [TradingAccount]) {
        latestKind = .generic
        latestAccountID = account.id
        AccountPersistedCacheCoordinator.noteAccountPatched(account, viewerID: account.ownerProfileID)
        revision += 1
    }

    func noteAccountsChanged(allAccounts: [TradingAccount], viewerID: ProfileID) {
        latestKind = .generic
        AccountPersistedCacheCoordinator.noteAccountsUpdated(allAccounts, viewerID: viewerID)
        revision += 1
    }

    /// Live ledger or funded prop payout recorded — Withdrawals history and Dashboard cycles refresh.
    func notePayoutRecorded(accountID: TradingAccountID) {
        latestKind = .payoutRecorded(accountID)
        latestAccountID = accountID
        revision += 1
    }

    func invalidate() {
        latestAccountID = nil
        latestKind = .generic
        revision = 0
    }
}
