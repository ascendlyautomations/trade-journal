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

    /// Dashboard hero account value, one definition for Eval, Live, and Funded prop.
    ///
    /// - Eval / Live / Sim: `startingBalance + lifetimeRealizedPnL` (manual ledger subtracts withdrawals on Live).
    /// - Funded prop (payout cycles): ``PropFirmStatusSnapshot/currentBalance`` when trade replay is available.
    static func dashboardAccountBalance(
        account: TradingAccount,
        startingBalance: Decimal,
        lifetimeRealizedPnL: Decimal,
        propFirmSnapshot: PropFirmStatusSnapshot?,
        manualPayoutEntries: [AccountPayoutEntry],
        propFirmTradeReplayCount: Int
    ) -> Decimal {
        if PropFirmPayoutPolicy.supportsRecordPayout(for: account),
           let snapshot = propFirmSnapshot,
           propFirmTradeReplayCount > 0
        {
            return snapshot.currentBalance
        }
        if usesManualLedgerForTrackedBalance(account: account) {
            return ledgerTrackedBalance(
                startingBalance: startingBalance,
                lifetimeRealizedPnL: lifetimeRealizedPnL,
                payoutEntries: manualPayoutEntries
            )
        }
        return startingBalance + lifetimeRealizedPnL
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

    /// Same rules as ``withdrawalSummary(account:payoutCycles:ledgerEntries:)`` but respects the dashboard date window.
    static func withdrawalSummary(
        account: TradingAccount,
        payoutCycles: [AccountPayoutCycle],
        ledgerEntries: [AccountPayoutEntry],
        scope: DashboardClientScopeFilter,
        now: Date = Date()
    ) -> WithdrawalSummary? {
        let scopedCycles = payoutCycles.filter {
            PayoutHistorySupport.matchesDashboardDate($0.endedAt ?? $0.startedAt, scope: scope, now: now)
        }
        let scopedLedger = ledgerEntries.filter {
            PayoutHistorySupport.matchesDashboardDate($0.payoutDate, scope: scope, now: now)
        }
        return withdrawalSummary(
            account: account,
            payoutCycles: scopedCycles,
            ledgerEntries: scopedLedger
        )
    }

    /// Dashboard equity hero when All Accounts is selected (per-account rules, no duplicate rows).
    static func aggregateWithdrawalSummary(
        accounts: [TradingAccount],
        cyclesByAccount: [TradingAccountID: [AccountPayoutCycle]],
        ledgerByAccount: [TradingAccountID: [AccountPayoutEntry]],
        scope: DashboardClientScopeFilter,
        now: Date = Date()
    ) -> WithdrawalSummary? {
        guard case .all = scope.accountFilter else { return nil }

        var totalCount = 0
        var totalAmount = Decimal.zero
        var sawPayouts = false
        var sawWithdrawals = false

        for account in accounts {
            guard DashboardAccountScopePolicy.includesAccountInDashboard(account) else { continue }
            guard matchesDashboardAccountModeFilter(account: account, scope: scope) else { continue }
            guard let partial = withdrawalSummary(
                account: account,
                payoutCycles: cyclesByAccount[account.id] ?? [],
                ledgerEntries: ledgerByAccount[account.id] ?? [],
                scope: scope,
                now: now
            ) else { continue }
            totalCount += partial.count
            totalAmount += partial.totalAmount
            switch partial.terminology {
            case .payouts: sawPayouts = true
            case .withdrawals: sawWithdrawals = true
            }
        }

        guard totalCount > 0, totalAmount > 0 else { return nil }

        let terminology: WithdrawalSummary.Terminology = {
            if sawPayouts && !sawWithdrawals { return .payouts }
            if sawWithdrawals && !sawPayouts { return .withdrawals }
            return .withdrawals
        }()

        return WithdrawalSummary(
            count: totalCount,
            totalAmount: totalAmount,
            terminology: terminology
        )
    }

    private static func matchesDashboardAccountModeFilter(
        account: TradingAccount,
        scope: DashboardClientScopeFilter
    ) -> Bool {
        let selected = scope.accountMode
        if selected == .all { return true }
        if selected == .backtest { return account.mode == .backtest }
        guard let target = selected.tradingAccountMode else { return true }
        return account.mode == target
    }
}
