import Foundation

/// Native port of web `lib/propfirmMetrics.ts` — behavioral source of truth.
///
/// Do not invent alternate formulas. Ambiguities (static DD, best-day consistency,
/// null daily_drawdown breach) are documented in Prop Firm phase notes.
nonisolated enum PropFirmMetrics {
    struct TradeInput: Sendable, Equatable, Identifiable {
        var id: String
        var pnl: Decimal
        var createdAt: Date?
        var entryAt: Date?
        var exitAt: Date?
    }

    struct PayoutCycleContext: Sendable, Equatable {
        var startedAt: Date?
        var cycleStartBalance: Decimal
        var initialDrawdownFloor: Decimal?
        var drawdownBehavior: String?
        var cycleNumber: Int?
    }

    struct TrailingDrawdownResult: Sendable, Equatable {
        var currentBalance: Decimal
        var peakBalance: Decimal
        var drawdownFloor: Decimal
        var distanceToDD: Decimal
        var maxDrawdownUsed: Decimal
        var breachedTrailingDD: Bool
    }

    struct ConsistencyResult: Sendable, Equatable {
        var biggestWin: Decimal
        var totalProfit: Decimal
        var allowedMax: Decimal
        var isConsistent: Bool
        var ruleActive: Bool
    }

    struct DailyMetrics: Sendable, Equatable {
        var winningDays: Int
        var todayPnL: Decimal
        var worstDay: Decimal
        var worstDailyLossUsed: Decimal
    }

    struct ProgressResult: Sendable, Equatable {
        var totalPnL: Decimal
        var progressPercent: Double
        var isPassed: Bool
        var isFailed: Bool
        var status: Status
        var ddPercent: Double
        var distanceDanger: Bool

        enum Status: String, Sendable {
            case passed = "PASSED"
            case failed = "FAILED"
            case inProgress = "IN PROGRESS"
        }
    }

    struct AccountMetrics: Sendable, Equatable {
        var startingBalance: Decimal
        var cycleDaily: DailyMetrics
        var cycleTrailing: TrailingDrawdownResult
        var cycleConsistency: ConsistencyResult
        var cycleProgress: ProgressResult
        var lifetimeTotalPnL: Decimal
        var cyclePnL: Decimal
        var lifetimeDaily: DailyMetrics
        var lifetimeTrailing: TrailingDrawdownResult
        var displayCurrentBalance: Decimal
        var payoutCycle: PayoutCycleContext
        var dailyDrawdownBreached: Bool
        var payoutReady: Bool
        var evalDisplayStatus: String
        var fundedDisplayStatus: String?
    }

    struct TrailingOptions: Sendable {
        var accountBaseBalance: Decimal?
        var initialDrawdownFloor: Decimal?
        var lockDrawdownFloor: Bool
    }

    // MARK: - Account size (web parseAccountSizeToNumber)

    static func parseAccountSize(_ money: Money?) -> Decimal {
        money?.amount ?? 0
    }

    static func parseAccountSizeString(_ raw: String?) -> Decimal {
        guard let raw else { return 0 }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        if let match = trimmed.range(of: #"^([\d.]+)\s*k$"#, options: [.regularExpression, .caseInsensitive]) {
            let numberPart = String(trimmed[match]).replacingOccurrences(
                of: #"\s*k$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            if let n = Decimal(string: numberPart) { return n * 1_000 }
        }
        return Decimal(string: trimmed) ?? 0
    }

    // MARK: - Trailing DD (web computeTrailingDrawdown)

    static func computeTrailingDrawdown(
        trades: [TradeInput],
        startingBalance: Decimal,
        maxDrawdown: Decimal,
        options: TrailingOptions? = nil
    ) -> TrailingDrawdownResult {
        let maxDd = maxDrawdown
        let accountBase = options?.accountBaseBalance ?? startingBalance
        let sorted = dedupe(trades).sorted {
            ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }

        var balance = startingBalance
        var peakBalance = startingBalance
        var drawdownFloor = options?.initialDrawdownFloor ?? (startingBalance - maxDd)
        var maxDrawdownUsed = Decimal(0)
        var breached = false
        let lockFloor = options?.lockDrawdownFloor ?? false

        for trade in sorted {
            balance += trade.pnl
            if balance > peakBalance {
                peakBalance = balance
                if !lockFloor {
                    drawdownFloor = min(accountBase, peakBalance - maxDd)
                }
            }
            let drawdownUsed = max(0, drawdownFloor + maxDd - balance)
            if drawdownUsed > maxDrawdownUsed { maxDrawdownUsed = drawdownUsed }
            if maxDd > 0, balance < drawdownFloor { breached = true }
        }

        return TrailingDrawdownResult(
            currentBalance: balance,
            peakBalance: peakBalance,
            drawdownFloor: drawdownFloor,
            distanceToDD: balance - drawdownFloor,
            maxDrawdownUsed: maxDrawdownUsed,
            breachedTrailingDD: breached
        )
    }

    // MARK: - Consistency (web computeConsistencyRule)

    static func computeConsistency(
        trades: [TradeInput],
        consistencyPercent: Decimal?
    ) -> ConsistencyResult {
        let ruleActive = {
            guard let pct = consistencyPercent else { return false }
            return pct > 0
        }()
        let pct = ruleActive ? (consistencyPercent ?? 0) : 0
        let winners = trades.filter { $0.pnl > 0 }
        let totalProfit = winners.reduce(Decimal(0)) { $0 + $1.pnl }
        let biggestWin = winners.map(\.pnl).max() ?? 0
        let allowedMax = ruleActive ? totalProfit * (pct / 100) : 0
        return ConsistencyResult(
            biggestWin: biggestWin,
            totalProfit: totalProfit,
            allowedMax: allowedMax,
            isConsistent: !ruleActive || biggestWin <= allowedMax,
            ruleActive: ruleActive
        )
    }

    // MARK: - Daily metrics

    static func isWinningTradingDay(
        dailyNetPnL: Decimal,
        winningDayThreshold: Decimal?
    ) -> Bool {
        if let threshold = winningDayThreshold, threshold > 0 {
            return dailyNetPnL >= threshold
        }
        return dailyNetPnL > 0
    }

    static func computeDailyMetrics(
        trades: [TradeInput],
        now: Date = Date(),
        winningDayThreshold: Decimal? = nil
    ) -> DailyMetrics {
        var map: [String: Decimal] = [:]
        for trade in trades.sorted(by: tradeSequence) {
            guard let day = PropFirmTradingDay.key(for: trade) else { continue }
            map[day, default: 0] += trade.pnl
        }
        let winningDays = map.values.filter { isWinningTradingDay(dailyNetPnL: $0, winningDayThreshold: winningDayThreshold) }.count
        let todayKey = PropFirmTradingDay.key(for: now) ?? ""
        let todayPnL = map[todayKey] ?? 0
        let values = Array(map.values)
        let worstDay = values.min() ?? 0
        let worstDailyLossUsed = worstDay < 0 ? abs(worstDay) : 0
        return DailyMetrics(
            winningDays: winningDays,
            todayPnL: todayPnL,
            worstDay: worstDay,
            worstDailyLossUsed: worstDailyLossUsed
        )
    }

    // MARK: - Progress / payout

    static func computeProgress(
        cyclePnL: Decimal,
        trailing: TrailingDrawdownResult,
        rules: PropFirmAccountRules?
    ) -> ProgressResult {
        let profitTarget = rules?.profitTarget ?? 0
        let maxDdLimit = rules?.maxDrawdown ?? 0
        let drawdownUsed = trailing.maxDrawdownUsed

        let progressPercent: Double = {
            guard profitTarget > 0 else { return 0 }
            let ratio = NSDecimalNumber(decimal: abs(cyclePnL) / profitTarget).doubleValue
            return min(ratio * 100, 100)
        }()

        let isPassed = rules != nil && profitTarget > 0 && cyclePnL >= profitTarget
        let isFailed = rules != nil
            && maxDdLimit > 0
            && (trailing.breachedTrailingDD || trailing.distanceToDD < 0)
        let status: ProgressResult.Status = isFailed ? .failed : (isPassed ? .passed : .inProgress)

        let ddPercent: Double = {
            guard maxDdLimit > 0 else { return 0 }
            let ratio = NSDecimalNumber(decimal: drawdownUsed / maxDdLimit).doubleValue
            return min(ratio * 100, 100)
        }()

        let distanceDanger = maxDdLimit > 0
            && trailing.distanceToDD >= 0
            && trailing.distanceToDD < (maxDdLimit * Decimal(string: "0.2")!)

        return ProgressResult(
            totalPnL: cyclePnL,
            progressPercent: progressPercent,
            isPassed: isPassed,
            isFailed: isFailed,
            status: status,
            ddPercent: ddPercent,
            distanceDanger: distanceDanger
        )
    }

    static func isPayoutReady(
        progress: ProgressResult,
        dailyDrawdownBreached: Bool,
        winningDaysRequired: Bool,
        winningDaysTargetMet: Bool,
        consistencyRequired: Bool,
        consistencyMet: Bool
    ) -> Bool {
        if progress.isFailed { return false }
        if dailyDrawdownBreached { return false }
        if !progress.isPassed { return false }
        if winningDaysRequired && !winningDaysTargetMet { return false }
        if consistencyRequired && !consistencyMet { return false }
        return true
    }

    /// Orchestrator — mirrors `computePropfirmAccountMetrics`.
    ///
    /// Payout cycle defaults to account inception (`startedAt == nil`) when
    /// `account_payout_cycles` has not been loaded yet.
    static func computeAccountMetrics(
        trades: [TradeInput],
        accountSize: Decimal,
        rules: PropFirmAccountRules?,
        payoutCycle: PayoutCycleContext? = nil,
        now: Date = Date()
    ) -> AccountMetrics {
        let startingBalance = accountSize
        let cycle = payoutCycle ?? PayoutCycleContext(
            startedAt: nil,
            cycleStartBalance: startingBalance,
            initialDrawdownFloor: nil,
            drawdownBehavior: rules?.payoutDrawdownBehavior,
            cycleNumber: nil
        )

        let unique = dedupe(trades)
        let threshold = rules?.winningDayThreshold
        let lifetimeDaily = computeDailyMetrics(trades: unique, now: now, winningDayThreshold: threshold)
        let lifetimePnL = unique.reduce(Decimal(0)) { $0 + $1.pnl }

        let maxDd = rules?.maxDrawdown ?? 0
        let lifetimeTrailing = computeTrailingDrawdown(
            trades: unique,
            startingBalance: startingBalance,
            maxDrawdown: maxDd
        )

        let cycleTrades = filterForCycle(unique, startedAt: cycle.startedAt)
        let cycleDaily = computeDailyMetrics(trades: cycleTrades, now: now, winningDayThreshold: threshold)
        let lockFloor = (cycle.drawdownBehavior == "reset_to_account") && cycle.initialDrawdownFloor != nil
        let cycleTrailing = computeTrailingDrawdown(
            trades: cycleTrades,
            startingBalance: cycle.cycleStartBalance,
            maxDrawdown: maxDd,
            options: TrailingOptions(
                accountBaseBalance: startingBalance,
                initialDrawdownFloor: cycle.initialDrawdownFloor,
                lockDrawdownFloor: lockFloor
            )
        )
        let consistency = computeConsistency(trades: cycleTrades, consistencyPercent: rules?.consistencyPercent)
        let cyclePnL = cycleTrailing.currentBalance - cycle.cycleStartBalance
        let progress = computeProgress(cyclePnL: cyclePnL, trailing: cycleTrailing, rules: rules)

        let displayBalance = cycle.startedAt == nil
            ? lifetimeTrailing.currentBalance
            : cycleTrailing.currentBalance

        // Web: `worstDailyLossUsed > Number(daily_drawdown)` — null coerces to 0.
        let dailyLimit = rules?.dailyDrawdown
        let dailyBreached: Bool = {
            let limit = dailyLimit ?? 0
            return cycleDaily.worstDailyLossUsed > limit
        }()

        let winningRequired = (rules?.winningDaysRequired ?? 0) > 0
        let winningMet = {
            guard let required = rules?.winningDaysRequired else { return true }
            return cycleDaily.winningDays >= required
        }()

        let payoutReady = isPayoutReady(
            progress: progress,
            dailyDrawdownBreached: dailyBreached,
            winningDaysRequired: winningRequired,
            winningDaysTargetMet: winningMet,
            consistencyRequired: consistency.ruleActive,
            consistencyMet: consistency.isConsistent
        )

        let evalStatus: String = {
            if progress.isPassed { return "PASSED" }
            if progress.isFailed { return "FAILED" }
            return "ACTIVE"
        }()

        let fundedStatus: String? = {
            if progress.isFailed { return "FAILED" }
            if payoutReady { return "PAYOUT_READY" }
            return nil
        }()

        return AccountMetrics(
            startingBalance: startingBalance,
            cycleDaily: cycleDaily,
            cycleTrailing: cycleTrailing,
            cycleConsistency: consistency,
            cycleProgress: progress,
            lifetimeTotalPnL: lifetimePnL,
            cyclePnL: cyclePnL,
            lifetimeDaily: lifetimeDaily,
            lifetimeTrailing: lifetimeTrailing,
            displayCurrentBalance: displayBalance,
            payoutCycle: cycle,
            dailyDrawdownBreached: dailyBreached,
            payoutReady: payoutReady,
            evalDisplayStatus: evalStatus,
            fundedDisplayStatus: fundedStatus
        )
    }

    // MARK: - Helpers

    private static func dedupe(_ trades: [TradeInput]) -> [TradeInput] {
        var seen = Set<String>()
        var out: [TradeInput] = []
        for trade in trades {
            if seen.insert(trade.id).inserted {
                out.append(trade)
            }
        }
        return out
    }

    private static func tradeSequence(_ a: TradeInput, _ b: TradeInput) -> Bool {
        let aDate = a.exitAt ?? a.entryAt ?? a.createdAt ?? .distantPast
        let bDate = b.exitAt ?? b.entryAt ?? b.createdAt ?? .distantPast
        return aDate < bDate
    }

    private static func filterForCycle(_ trades: [TradeInput], startedAt: Date?) -> [TradeInput] {
        guard let startedAt else { return trades }
        return trades.filter { trade in
            let stamp = trade.exitAt ?? trade.entryAt ?? trade.createdAt
            guard let stamp else { return false }
            return stamp >= startedAt
        }
    }

    static func tradeInputs(from trades: [Trade]) -> [TradeInput] {
        trades.map {
            TradeInput(
                id: $0.id.rawValue,
                pnl: $0.realizedPnL?.amount ?? 0,
                createdAt: $0.createdAt,
                entryAt: $0.entryAt,
                exitAt: $0.exitAt
            )
        }
    }
}

/// Futures trading day key — web `getTradingDayKey` (6 PM America/New_York rollover).
nonisolated enum PropFirmTradingDay {
    private static let timeZone = TimeZone(identifier: "America/New_York") ?? .gmt

    static func key(for trade: PropFirmMetrics.TradeInput) -> String? {
        let date = trade.exitAt ?? trade.entryAt ?? trade.createdAt
        guard let date else { return nil }
        return key(for: date)
    }

    static func key(for date: Date) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var comps = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let hour = comps.hour else { return nil }
        if hour >= 18 {
            guard let day = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: timeZone,
                year: comps.year,
                month: comps.month,
                day: comps.day
            )),
            let next = calendar.date(byAdding: .day, value: 1, to: day)
            else { return nil }
            comps = calendar.dateComponents([.year, .month, .day], from: next)
        }
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
