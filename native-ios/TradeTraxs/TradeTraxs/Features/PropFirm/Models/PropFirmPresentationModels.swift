import Foundation

/// Dashboard / detail presentation snapshot derived from ``PropFirmMetrics``.
nonisolated struct PropFirmStatusSnapshot: Hashable, Sendable, Identifiable {
    var id: TradingAccountID { accountID }
    var accountID: TradingAccountID
    var accountName: String
    var phaseLabel: String
    var statusLabel: String
    var startingBalance: Decimal
    var currentBalance: Decimal
    var cyclePnL: Decimal
    var distanceToDD: Decimal
    var drawdownFloor: Decimal
    var maxDrawdownLimit: Decimal?
    var dailyLossUsed: Decimal
    var dailyLossLimit: Decimal?
    var profitTarget: Decimal?
    var profitTargetProgress: Double
    var winningDays: Int
    var winningDaysRequired: Int?
    var consistencyRequired: Bool
    var consistencyMet: Bool
    var isFailed: Bool
    var isPassed: Bool
    var payoutReady: Bool
    var distanceDanger: Bool
    var dailyDrawdownBreached: Bool

    var riskTone: DashboardMetricTone {
        if isFailed || dailyDrawdownBreached { return .negative }
        if distanceDanger { return .negative }
        if isPassed || payoutReady { return .positive }
        return .neutral
    }

    static func build(
        account: TradingAccount,
        trades: [Trade]
    ) -> PropFirmStatusSnapshot? {
        guard account.isPropFirmAccount else { return nil }
        let rules = account.propFirmRules ?? PropFirmAccountRules()
        let size = PropFirmMetrics.parseAccountSize(account.size)
        // Prop metrics use the account trade universe — not Dashboard date range.
        let accountTrades = trades.filter { $0.accountID == account.id }
        let metrics = PropFirmMetrics.computeAccountMetrics(
            trades: PropFirmMetrics.tradeInputs(from: accountTrades),
            accountSize: size,
            rules: rules
        )

        let phaseLabel: String = {
            switch account.mode {
            case .evaluation: return "Evaluation"
            case .funded: return "Funded"
            default: return account.mode.rawValue.capitalized
            }
        }()

        let statusLabel: String = {
            if account.mode == .funded {
                if let funded = metrics.fundedDisplayStatus {
                    return funded.replacingOccurrences(of: "_", with: " ")
                }
                return metrics.cycleProgress.status.rawValue
            }
            return metrics.evalDisplayStatus
        }()

        return PropFirmStatusSnapshot(
            accountID: account.id,
            accountName: TradingAccountDisplay.title(for: account, audience: .owner),
            phaseLabel: phaseLabel,
            statusLabel: statusLabel,
            startingBalance: metrics.startingBalance,
            currentBalance: metrics.displayCurrentBalance,
            cyclePnL: metrics.cyclePnL,
            distanceToDD: metrics.cycleTrailing.distanceToDD,
            drawdownFloor: metrics.cycleTrailing.drawdownFloor,
            maxDrawdownLimit: rules.maxDrawdown,
            dailyLossUsed: metrics.cycleDaily.worstDailyLossUsed,
            dailyLossLimit: rules.dailyDrawdown,
            profitTarget: rules.profitTarget,
            profitTargetProgress: metrics.cycleProgress.progressPercent,
            winningDays: metrics.cycleDaily.winningDays,
            winningDaysRequired: rules.winningDaysRequired,
            consistencyRequired: metrics.cycleConsistency.ruleActive,
            consistencyMet: metrics.cycleConsistency.isConsistent,
            isFailed: metrics.cycleProgress.isFailed,
            isPassed: metrics.cycleProgress.isPassed,
            payoutReady: metrics.payoutReady,
            distanceDanger: metrics.cycleProgress.distanceDanger,
            dailyDrawdownBreached: metrics.dailyDrawdownBreached
        )
    }
}
