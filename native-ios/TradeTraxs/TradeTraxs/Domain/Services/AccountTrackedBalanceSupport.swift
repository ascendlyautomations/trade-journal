import Foundation

/// Tracked account value for manual-ledger withdrawals (`account_payout_entries`).
///
/// Prop funded payouts use `account_payout_cycles` + ``PropFirmMetrics`` instead.
nonisolated enum AccountTrackedBalanceSupport {
    static func totalManualWithdrawals(from entries: [AccountPayoutEntry]) -> Decimal {
        entries.reduce(into: Decimal.zero) { partial, entry in
            partial += entry.amount.amount
        }
    }

    /// `starting + lifetime realized P&L − sum(manual ledger withdrawals)`.
    static func ledgerTrackedBalance(
        startingBalance: Decimal,
        lifetimeRealizedPnL: Decimal,
        payoutEntries: [AccountPayoutEntry]
    ) -> Decimal {
        let withdrawals = totalManualWithdrawals(from: payoutEntries)
        return startingBalance + lifetimeRealizedPnL - withdrawals
    }

    /// Accounts whose balance should subtract manual ledger rows (Live, etc.).
    static func usesManualLedgerForTrackedBalance(account: TradingAccount) -> Bool {
        PropFirmPayoutPolicy.supportsManualPayoutLedger(for: account)
    }

    /// Lifetime withdrawal summary for Dashboard Account Value (not timeframe-scoped).
    nonisolated struct WithdrawalSummary: Hashable, Sendable {
        enum Terminology: Hashable, Sendable {
            case payouts
            case withdrawals
        }

        var count: Int
        var totalAmount: Decimal
        var terminology: Terminology

        func compactLabel(formattedTotal: String) -> String {
            let noun: String = {
                switch terminology {
                case .payouts:
                    return count == 1 ? "Payout" : "Payouts"
                case .withdrawals:
                    return count == 1 ? "Withdrawal" : "Withdrawals"
                }
            }()
            return "\(count) \(noun) • \(formattedTotal)"
        }
    }

    static func withdrawalSummary(
        account: TradingAccount,
        payoutCycles: [AccountPayoutCycle],
        ledgerEntries: [AccountPayoutEntry]
    ) -> WithdrawalSummary? {
        if PropFirmPayoutPolicy.supportsRecordPayout(for: account) {
            let completed = PropFirmPayoutCycleSupport.selectCompletedPayoutHistory(payoutCycles)
            let total = completed.reduce(into: Decimal.zero) { partial, cycle in
                partial += cycle.payoutAmount ?? 0
            }
            guard !completed.isEmpty, total > 0 else { return nil }
            return WithdrawalSummary(
                count: completed.count,
                totalAmount: total,
                terminology: .payouts
            )
        }
        if usesManualLedgerForTrackedBalance(account: account) {
            guard !ledgerEntries.isEmpty else { return nil }
            let total = totalManualWithdrawals(from: ledgerEntries)
            guard total > 0 else { return nil }
            return WithdrawalSummary(
                count: ledgerEntries.count,
                totalAmount: total,
                terminology: .withdrawals
            )
        }
        return nil
    }
}
