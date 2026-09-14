import Foundation

/// Unified payout history row — manual ledger + funded prop-firm cycles.
nonisolated struct PayoutHistoryItem: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        case liveLedger
        case otherLedger
        case fundedCycle
    }

    var id: String
    var amount: Decimal
    var date: Date
    var accountID: TradingAccountID
    var ledgerEntryID: AccountPayoutEntryID?
    var source: Source
    var note: String?

    var isEditable: Bool { ledgerEntryID != nil }
}

nonisolated enum PayoutHistorySupport {
    static func buildHistory(
        accounts: [TradingAccount],
        entriesByAccount: [TradingAccountID: [AccountPayoutEntry]],
        cyclesByAccount: [TradingAccountID: [AccountPayoutCycle]]
    ) -> [PayoutHistoryItem] {
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        var items: [PayoutHistoryItem] = []

        for (accountID, entries) in entriesByAccount {
            let account = accountsByID[accountID]
            let source: PayoutHistoryItem.Source = account.map { account in
                PropFirmPayoutPolicy.supportsLiveWithdrawal(for: account) ? .liveLedger : .otherLedger
            } ?? .otherLedger
            for entry in entries {
                items.append(
                    PayoutHistoryItem(
                        id: "ledger:\(entry.id.rawValue)",
                        amount: entry.amount.amount,
                        date: entry.payoutDate,
                        accountID: accountID,
                        ledgerEntryID: entry.id,
                        source: source,
                        note: entry.note
                    )
                )
            }
        }

        for (accountID, cycles) in cyclesByAccount {
            let completed = PropFirmPayoutCycleSupport.selectCompletedPayoutHistory(cycles)
            for cycle in completed {
                guard let amount = cycle.payoutAmount, amount > 0 else { continue }
                let date = cycle.endedAt ?? cycle.startedAt
                items.append(
                    PayoutHistoryItem(
                        id: "cycle:\(cycle.id)",
                        amount: amount,
                        date: date,
                        accountID: accountID,
                        ledgerEntryID: nil,
                        source: .fundedCycle,
                        note: nil
                    )
                )
            }
        }

        return items.sorted { $0.date > $1.date }
    }

    static func summary(for items: [PayoutHistoryItem]) -> (total: Decimal, count: Int, average: Decimal?) {
        guard !items.isEmpty else { return (0, 0, nil) }
        let total = items.reduce(Decimal.zero) { $0 + $1.amount }
        let count = items.count
        let average = total / Decimal(count)
        return (total, count, average)
    }

    static func liveWithdrawals(
        from items: [PayoutHistoryItem],
        accountsByID: [TradingAccountID: TradingAccount]
    ) -> [PayoutHistoryItem] {
        items
            .filter { isLiveWithdrawal($0, account: accountsByID[$0.accountID]) }
            .sorted { $0.date > $1.date }
    }

    static func propPayouts(
        from items: [PayoutHistoryItem],
        accountsByID: [TradingAccountID: TradingAccount]
    ) -> [PayoutHistoryItem] {
        items
            .filter { isPropPayout($0, account: accountsByID[$0.accountID]) }
            .sorted { $0.date > $1.date }
    }

    static func isLiveWithdrawal(_ item: PayoutHistoryItem, account: TradingAccount?) -> Bool {
        switch item.source {
        case .fundedCycle:
            return false
        case .liveLedger:
            return true
        case .otherLedger:
            return account?.mode == .live
        }
    }

    static func isPropPayout(_ item: PayoutHistoryItem, account: TradingAccount?) -> Bool {
        switch item.source {
        case .fundedCycle:
            return true
        case .liveLedger:
            return false
        case .otherLedger:
            return account?.mode == .funded
        }
    }
}
