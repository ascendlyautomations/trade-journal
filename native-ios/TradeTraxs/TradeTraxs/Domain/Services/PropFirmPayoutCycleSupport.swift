import Foundation

/// Native port of web `lib/propfirmPayoutCycles.ts` helpers used by Record Payout.
nonisolated enum PropFirmPayoutCycleSupport {
    static func selectActivePayoutCycle(_ cycles: [AccountPayoutCycle]) -> AccountPayoutCycle? {
        cycles.first { $0.endedAt == nil }
    }

    static func selectCompletedPayoutHistory(_ cycles: [AccountPayoutCycle]) -> [AccountPayoutCycle] {
        cycles
            .filter { cycle in
                cycle.endedAt != nil
                    && (cycle.payoutAmount ?? 0) > 0
            }
            .sorted { lhs, rhs in
                (lhs.endedAt ?? .distantPast) > (rhs.endedAt ?? .distantPast)
            }
    }

    static func buildPayoutCycleContext(
        activeCycle: AccountPayoutCycle?,
        accountStartingBalance: Decimal
    ) -> PropFirmMetrics.PayoutCycleContext {
        guard let activeCycle else {
            return PropFirmMetrics.PayoutCycleContext(
                startedAt: nil,
                cycleStartBalance: accountStartingBalance,
                initialDrawdownFloor: nil,
                drawdownBehavior: nil,
                cycleNumber: nil
            )
        }
        return PropFirmMetrics.PayoutCycleContext(
            startedAt: activeCycle.startedAt,
            cycleStartBalance: activeCycle.cycleStartBalance,
            initialDrawdownFloor: activeCycle.drawdownFloorAfterPayout,
            drawdownBehavior: activeCycle.drawdownBehavior?.rawValue,
            cycleNumber: activeCycle.cycleNumber
        )
    }

    static func resolveDefaultPayoutDrawdownBehavior(
        account: TradingAccount,
        activeCycle: AccountPayoutCycle?
    ) -> PayoutDrawdownBehavior {
        if let behavior = activeCycle?.drawdownBehavior {
            return behavior
        }
        if let raw = account.propFirmRules?.payoutDrawdownBehavior,
           let behavior = PayoutDrawdownBehavior(rawValue: raw) {
            return behavior
        }
        return .resetToAccount
    }

    static func buildSetupContext(
        account: TradingAccount,
        trades: [Trade],
        payoutCycles: [AccountPayoutCycle],
        now: Date = Date()
    ) -> PropFirmPayoutSetupContext {
        let startingBalance = PropFirmMetrics.parseAccountSize(account.size)
        let activeCycle = selectActivePayoutCycle(payoutCycles)
        let cycleContext = buildPayoutCycleContext(
            activeCycle: activeCycle,
            accountStartingBalance: startingBalance
        )
        let rules = account.propFirmRules ?? PropFirmAccountRules()
        let metrics = PropFirmMetrics.computeAccountMetrics(
            trades: PropFirmMetrics.tradeInputs(from: trades.filter { $0.accountID == account.id }),
            accountSize: startingBalance,
            rules: rules,
            payoutCycle: cycleContext,
            now: now
        )
        return PropFirmPayoutSetupContext(
            account: account,
            activeCycle: activeCycle,
            startingBalance: metrics.startingBalance,
            balanceBeforePayout: metrics.lifetimeTrailing.currentBalance,
            defaultDrawdownBehavior: resolveDefaultPayoutDrawdownBehavior(
                account: account,
                activeCycle: activeCycle
            ),
            defaultRememberDrawdownBehavior: false,
            cycleTrailingMetrics: metrics.cycleTrailing
        )
    }

    static func milestoneAchievementPrefill(
        account: TradingAccount,
        payoutAmount: Decimal,
        payoutDate: Date,
        note: String? = nil,
        withdrawalLink: WithdrawalAchievementLinkage.Source? = nil
    ) -> CreateAchievementPrefill {
        let firm = TradingAccountDisplay.propFirmName(for: account) ?? account.name
        let title = firm.isEmpty ? "\(account.name) Payout" : "\(firm) Payout"
        return CreateAchievementPrefill(
            kind: .propFirmPayout,
            titleText: title,
            descriptionText: trimmedAchievementNote(note),
            payoutAmountText: NSDecimalNumber(decimal: payoutAmount).stringValue,
            achievedAt: payoutDate,
            selectedAccountID: account.id,
            isPublic: true,
            lockKind: true,
            withdrawalLink: withdrawalLink
        )
    }

    /// Manual ledger withdrawal (`account_payout_entries`) — social achievement only; ledger row already saved.
    static func liveWithdrawalAchievementPrefill(
        account: TradingAccount,
        draft: AccountPayoutEntryDraft,
        withdrawalLink: WithdrawalAchievementLinkage.Source? = nil
    ) -> CreateAchievementPrefill {
        let title = TradingAccountDisplay.title(for: account, audience: .owner)
        return CreateAchievementPrefill(
            kind: .liveTradingPayout,
            titleText: title.isEmpty ? "Live Withdrawal" : "\(title) Withdrawal",
            descriptionText: trimmedAchievementNote(draft.note),
            payoutAmountText: draft.amountDigits.trimmingCharacters(in: .whitespacesAndNewlines),
            achievedAt: draft.payoutDate,
            selectedAccountID: account.id,
            isPublic: true,
            lockKind: true,
            withdrawalLink: withdrawalLink
        )
    }

    /// Prefill for Dashboard withdrawal detail or post-record prompts (read-only history → social post).
    static func achievementPrefill(
        for item: PayoutHistoryItem,
        account: TradingAccount
    ) -> CreateAchievementPrefill? {
        guard let link = WithdrawalAchievementLinkage.source(for: item) else { return nil }
        if PayoutHistorySupport.isPropPayout(item, account: account) {
            return milestoneAchievementPrefill(
                account: account,
                payoutAmount: item.amount,
                payoutDate: item.date,
                note: item.note,
                withdrawalLink: link
            )
        }
        let title = TradingAccountDisplay.title(for: account, audience: .owner)
        return CreateAchievementPrefill(
            kind: .liveTradingPayout,
            titleText: title.isEmpty ? "Live Withdrawal" : "\(title) Withdrawal",
            descriptionText: trimmedAchievementNote(item.note),
            payoutAmountText: NSDecimalNumber(decimal: item.amount).stringValue,
            achievedAt: item.date,
            selectedAccountID: account.id,
            isPublic: true,
            lockKind: true,
            withdrawalLink: link
        )
    }

    private static func trimmedAchievementNote(_ raw: String?) -> String {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
