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
    var completedPayoutHistory: [AccountPayoutCycle] = []

    // Detail presentation — authoritative rules + live cycle metrics.
    var firmName: String = ""
    var configuredAccountSize: Decimal = 0
    var cycleStartBalance: Decimal = 0
    var peakBalance: Decimal = 0
    var maxDrawdownUsed: Decimal = 0
    var consistencyPercent: Decimal?
    var consistencyBiggestWin: Decimal = 0
    var consistencyTotalProfit: Decimal = 0
    var consistencyAllowedMax: Decimal = 0
    var winningDayThreshold: Decimal?
    var payoutDrawdownBehaviorRaw: String?
    var accountNote: String?
    var publicStatusLabel: String?
    var isFunded: Bool = false
    var supportsRecordPayout: Bool = false
    var winningDaysTargetMet: Bool = true
    var profitTargetConfigured: Bool = false

    var riskTone: DashboardMetricTone {
        if isFailed || dailyDrawdownBreached { return .negative }
        if distanceDanger { return .negative }
        if isPassed || payoutReady { return .positive }
        return .neutral
    }

    static func build(
        account: TradingAccount,
        trades: [Trade],
        payoutCycles: [AccountPayoutCycle] = []
    ) -> PropFirmStatusSnapshot? {
        guard account.isPropFirmAccount else { return nil }
        let rules = account.propFirmRules ?? PropFirmAccountRules()
        let size = PropFirmMetrics.parseAccountSize(account.size)
        let accountTrades = trades.filter { $0.accountID == account.id }
        let activeCycle = PropFirmPayoutCycleSupport.selectActivePayoutCycle(payoutCycles)
        let cycleContext = PropFirmPayoutCycleSupport.buildPayoutCycleContext(
            activeCycle: activeCycle,
            accountStartingBalance: size
        )
        let metrics = PropFirmMetrics.computeAccountMetrics(
            trades: PropFirmMetrics.tradeInputs(from: accountTrades),
            accountSize: size,
            rules: rules,
            payoutCycle: cycleContext
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

        let winningMet: Bool = {
            guard let required = rules.winningDaysRequired, required > 0 else { return true }
            return metrics.cycleDaily.winningDays >= required
        }()

        let profitTarget = rules.profitTarget
        let profitConfigured = (profitTarget ?? 0) > 0

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
            profitTarget: profitTarget,
            profitTargetProgress: metrics.cycleProgress.progressPercent,
            winningDays: metrics.cycleDaily.winningDays,
            winningDaysRequired: rules.winningDaysRequired,
            consistencyRequired: metrics.cycleConsistency.ruleActive,
            consistencyMet: metrics.cycleConsistency.isConsistent,
            isFailed: metrics.cycleProgress.isFailed,
            isPassed: metrics.cycleProgress.isPassed,
            payoutReady: metrics.payoutReady,
            distanceDanger: metrics.cycleProgress.distanceDanger,
            dailyDrawdownBreached: metrics.dailyDrawdownBreached,
            completedPayoutHistory: PropFirmPayoutCycleSupport.selectCompletedPayoutHistory(payoutCycles),
            firmName: TradingAccountDisplay.inferPropFirmName(account.name),
            configuredAccountSize: size,
            cycleStartBalance: cycleContext.cycleStartBalance,
            peakBalance: metrics.cycleTrailing.peakBalance,
            maxDrawdownUsed: metrics.cycleTrailing.maxDrawdownUsed,
            consistencyPercent: rules.consistencyPercent,
            consistencyBiggestWin: metrics.cycleConsistency.biggestWin,
            consistencyTotalProfit: metrics.cycleConsistency.totalProfit,
            consistencyAllowedMax: metrics.cycleConsistency.allowedMax,
            winningDayThreshold: rules.winningDayThreshold,
            payoutDrawdownBehaviorRaw: rules.payoutDrawdownBehavior,
            accountNote: account.note,
            publicStatusLabel: account.customPublicStatus,
            isFunded: account.mode == .funded,
            supportsRecordPayout: PropFirmPayoutPolicy.supportsRecordPayout(for: account),
            winningDaysTargetMet: winningMet,
            profitTargetConfigured: profitConfigured
        )
    }
}
