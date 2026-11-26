import Foundation

/// Single-account dashboard hero equity, mirrors web `computeLiveAccountEquityChartData` with daily closes on long presets.
nonisolated enum DashboardAccountEquityChartEngine {
    struct EquitySample: Sendable, Equatable {
        var date: Date
        var equity: Decimal
        var drawdownFloor: Decimal?
    }

    enum Granularity: Sendable {
        case tradeLevel
        case dailyClose
    }

    struct PeriodContext: Sendable {
        var dateRange: DashboardDateRange
        var customInterval: DateInterval?
        var now: Date = Date()
    }

    static func granularity(
        dateRange: DashboardDateRange,
        customInterval: DateInterval?
    ) -> Granularity {
        if customInterval != nil { return .tradeLevel }
        switch dateRange {
        case .sevenDays:
            return .tradeLevel
        case .thirtyDays, .ninetyDays, .oneYear, .ytd, .all:
            return .dailyClose
        }
    }

    /// Largest peak-to-trough decline on a balance series (non-negative depth).
    static func peakToTroughDecline(from samples: [EquitySample]) -> Decimal {
        guard let first = samples.first else { return 0 }
        var peak = first.equity
        var maxDecline = Decimal.zero
        for sample in samples {
            if sample.equity > peak { peak = sample.equity }
            let decline = peak - sample.equity
            if decline > maxDecline { maxDecline = decline }
        }
        return maxDecline
    }

    static func computeEquitySeries(
        account: TradingAccount,
        lifetimeTrades: [Trade],
        ledgerEntries: [AccountPayoutEntry],
        payoutCycles: [AccountPayoutCycle],
        period: PeriodContext,
        granularityOverride: Granularity? = nil,
        includesBacktestTrades: Bool = false
    ) -> [EquitySample] {
        let startingBalance = PropFirmMetrics.parseAccountSize(account.size)
        let accountID = account.id
        let lifetime = lifetimeTrades.filter {
            $0.accountID == accountID && tradeMatchesEnginePolicy($0, includesBacktestTrades: includesBacktestTrades)
        }
        guard !lifetime.isEmpty || !ledgerEntries.isEmpty || !payoutCycles.isEmpty else {
            if startingBalance > 0 {
                return [EquitySample(date: period.now, equity: startingBalance, drawdownFloor: nil)]
            }
            return []
        }

        let periodStartMs = resolvePeriodStartMs(period)
        let periodEndMs = resolvePeriodEndMs(period)
        let hasPeriodWindow = periodStartMs != nil

        var openingBalance = startingBalance
        for trade in lifetime.sorted(by: tradeChronological) {
            if tradeIsBeforePeriod(trade, periodStartMs: periodStartMs, period: period) {
                openingBalance += trade.realizedPnL?.amount ?? 0
            }
        }
        for entry in ledgerEntries where entry.accountID == accountID {
            if withdrawalIsBeforePeriod(entry.payoutDate, periodStartMs: periodStartMs, period: period) {
                openingBalance -= entry.amount.amount
            }
        }
        for cycle in payoutCycles where cycle.accountID == accountID {
            guard let endedAt = cycle.endedAt,
                  let amount = cycle.payoutAmount,
                  amount > 0
            else { continue }
            if withdrawalIsBeforePeriod(endedAt, periodStartMs: periodStartMs, period: period) {
                openingBalance -= amount
            }
        }

        let inPeriodEvents = buildInPeriodEvents(
            account: account,
            lifetime: lifetime,
            ledgerEntries: ledgerEntries,
            payoutCycles: payoutCycles,
            period: period
        )

        var tradeLevel = replayTradeLevel(
            startingBalance: startingBalance,
            openingBalance: openingBalance,
            events: inPeriodEvents,
            hasPeriodWindow: hasPeriodWindow,
            periodStartMs: periodStartMs,
            periodEndMs: periodEndMs
        )

        let resolvedGranularity = granularityOverride
            ?? granularity(dateRange: period.dateRange, customInterval: period.customInterval)
        if resolvedGranularity == .dailyClose {
            tradeLevel = collapseToDailyClosing(tradeLevel, account: account)
        }

        return tradeLevel
    }

    /// All Accounts, combined balance progression (sum of sizes + chronological P&amp;L and payouts).
    static func computeAllAccountsEquitySeries(
        accounts: [TradingAccount],
        lifetimeTrades: [Trade],
        ledgerEntries: [AccountPayoutEntry],
        payoutCycles: [AccountPayoutCycle],
        period: PeriodContext,
        includesBacktestTrades: Bool = false
    ) -> [EquitySample] {
        let lifetime = lifetimeTrades.filter {
            tradeMatchesEnginePolicy($0, includesBacktestTrades: includesBacktestTrades)
        }
        let startingBalance = accounts.reduce(Decimal.zero) {
            $0 + PropFirmMetrics.parseAccountSize($1.size)
        }

        let periodStartMs = resolvePeriodStartMs(period)
        let periodEndMs = resolvePeriodEndMs(period)
        let hasPeriodWindow = periodStartMs != nil

        var openingBalance = startingBalance
        for trade in lifetime.sorted(by: tradeChronological) {
            if tradeIsBeforePeriod(trade, periodStartMs: periodStartMs, period: period) {
                openingBalance += trade.realizedPnL?.amount ?? 0
            }
        }
        for entry in ledgerEntries {
            if withdrawalIsBeforePeriod(entry.payoutDate, periodStartMs: periodStartMs, period: period) {
                openingBalance -= entry.amount.amount
            }
        }
        for cycle in payoutCycles {
            guard let endedAt = cycle.endedAt,
                  let amount = cycle.payoutAmount,
                  amount > 0
            else { continue }
            if withdrawalIsBeforePeriod(endedAt, periodStartMs: periodStartMs, period: period) {
                openingBalance -= amount
            }
        }

        let events = buildAllAccountsInPeriodEvents(
            lifetime: lifetime,
            ledgerEntries: ledgerEntries,
            payoutCycles: payoutCycles,
            period: period
        )

        return replayTradeLevel(
            startingBalance: startingBalance,
            openingBalance: openingBalance,
            events: events,
            hasPeriodWindow: hasPeriodWindow,
            periodStartMs: periodStartMs,
            periodEndMs: periodEndMs
        )
    }

    /// Trade-level balance path for Max Drawdown (never daily-collapsed).
    static func computeTradeLevelEquityForMaxDrawdown(
        accountFilter: DashboardAccountFilter,
        accounts: [TradingAccount],
        lifetimeTrades: [Trade],
        ledgerEntries: [AccountPayoutEntry],
        payoutCycles: [AccountPayoutCycle],
        period: PeriodContext
    ) -> [EquitySample] {
        switch accountFilter {
        case .all:
            return computeAllAccountsEquitySeries(
                accounts: accounts,
                lifetimeTrades: lifetimeTrades,
                ledgerEntries: ledgerEntries,
                payoutCycles: payoutCycles,
                period: period
            )
        case .account(let accountID):
            guard let account = accounts.first(where: { $0.id == accountID }) else { return [] }
            let cycles = payoutCycles.filter { $0.accountID == accountID }
            let ledger = ledgerEntries.filter { $0.accountID == accountID }
            return computeEquitySeries(
                account: account,
                lifetimeTrades: lifetimeTrades,
                ledgerEntries: ledger,
                payoutCycles: cycles,
                period: period,
                granularityOverride: .tradeLevel
            )
        case .copyTradingAll, .copyTradingGroup:
            let accountIDs = Set(lifetimeTrades.compactMap(\.accountID))
            let scopedAccounts = accounts.filter { accountIDs.contains($0.id) }
            return computeAllAccountsEquitySeries(
                accounts: scopedAccounts,
                lifetimeTrades: lifetimeTrades,
                ledgerEntries: ledgerEntries,
                payoutCycles: payoutCycles,
                period: period
            )
        }
    }

    static func mapToEquityPoints(_ samples: [EquitySample]) -> [ProfileStatisticsMetrics.EquityPoint] {
        ProfileStatisticsMetrics.chartOrderedEquityPoints(
            samples.enumerated().map { offset, sample in
                ProfileStatisticsMetrics.EquityPoint(
                    index: offset,
                    equity: sample.equity,
                    date: sample.date,
                    drawdownFloor: sample.drawdownFloor
                )
            }
        )
    }

    /// Merges prop-firm floor samples (trade-level replay) onto the displayed equity series by last-known floor.
    static func attachPropFirmDrawdownFloors(
        equitySamples: [EquitySample],
        floorSamples: [PropFirmDrawdownEquityEngine.EquitySample]
    ) -> [EquitySample] {
        attachChronologicalDrawdownFloors(
            equitySamples: equitySamples,
            floorDates: floorSamples.map { ($0.date, $0.drawdownFloor) }
        )
    }

    /// Picks the floor last known at or before each equity timestamp, never a future high-water floor.
    static func attachChronologicalDrawdownFloors(
        equitySamples: [EquitySample],
        floorDates: [(date: Date, floor: Decimal)]
    ) -> [EquitySample] {
        guard !equitySamples.isEmpty, !floorDates.isEmpty else { return equitySamples }
        let orderedFloors = floorDates.sorted { $0.date < $1.date }
        return equitySamples.map { sample in
            let ms = Int64(sample.date.timeIntervalSince1970 * 1000)
            let floor = orderedFloors.last {
                Int64($0.date.timeIntervalSince1970 * 1000) <= ms
            }?.floor ?? orderedFloors[0].floor
            return EquitySample(date: sample.date, equity: sample.equity, drawdownFloor: floor)
        }
    }

    // MARK: - Events

    private enum EventKind { case trade, withdrawal }

    private struct TimelineEvent {
        var sortMs: Int64
        var date: Date
        var delta: Decimal
        var kind: EventKind
    }

    private static func buildAllAccountsInPeriodEvents(
        lifetime: [Trade],
        ledgerEntries: [AccountPayoutEntry],
        payoutCycles: [AccountPayoutCycle],
        period: PeriodContext
    ) -> [TimelineEvent] {
        var events: [TimelineEvent] = []

        for trade in lifetime where tradeMatchesPeriod(trade, period: period) {
            let stamp = DashboardScopeFilterSupport.dashboardTradeFilterDate(for: trade)
            events.append(
                TimelineEvent(
                    sortMs: Int64(stamp.timeIntervalSince1970 * 1000),
                    date: stamp,
                    delta: trade.realizedPnL?.amount ?? 0,
                    kind: .trade
                )
            )
        }

        for entry in ledgerEntries where withdrawalMatchesPeriod(entry.payoutDate, period: period) {
            events.append(
                TimelineEvent(
                    sortMs: Int64(entry.payoutDate.timeIntervalSince1970 * 1000),
                    date: entry.payoutDate,
                    delta: -entry.amount.amount,
                    kind: .withdrawal
                )
            )
        }

        for cycle in payoutCycles {
            guard let endedAt = cycle.endedAt,
                  let amount = cycle.payoutAmount,
                  amount > 0,
                  withdrawalMatchesPeriod(endedAt, period: period)
            else { continue }
            events.append(
                TimelineEvent(
                    sortMs: Int64(endedAt.timeIntervalSince1970 * 1000),
                    date: endedAt,
                    delta: -amount,
                    kind: .withdrawal
                )
            )
        }

        return events.sorted { lhs, rhs in
            if lhs.sortMs != rhs.sortMs { return lhs.sortMs < rhs.sortMs }
            if lhs.kind == rhs.kind { return false }
            return lhs.kind == .trade
        }
    }

    private static func buildInPeriodEvents(
        account: TradingAccount,
        lifetime: [Trade],
        ledgerEntries: [AccountPayoutEntry],
        payoutCycles: [AccountPayoutCycle],
        period: PeriodContext
    ) -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        let accountID = account.id

        for trade in lifetime where tradeMatchesPeriod(trade, period: period) {
            let stamp = DashboardScopeFilterSupport.dashboardTradeFilterDate(for: trade)
            let sortMs = Int64(stamp.timeIntervalSince1970 * 1000)
            events.append(
                TimelineEvent(
                    sortMs: sortMs,
                    date: stamp,
                    delta: trade.realizedPnL?.amount ?? 0,
                    kind: .trade
                )
            )
        }

        for entry in ledgerEntries where entry.accountID == accountID {
            if withdrawalMatchesPeriod(entry.payoutDate, period: period) {
                let sortMs = Int64(entry.payoutDate.timeIntervalSince1970 * 1000)
                events.append(
                    TimelineEvent(
                        sortMs: sortMs,
                        date: entry.payoutDate,
                        delta: -entry.amount.amount,
                        kind: .withdrawal
                    )
                )
            }
        }

        for cycle in payoutCycles where cycle.accountID == accountID {
            guard let endedAt = cycle.endedAt,
                  let amount = cycle.payoutAmount,
                  amount > 0,
                  withdrawalMatchesPeriod(endedAt, period: period)
            else { continue }
            events.append(
                TimelineEvent(
                    sortMs: Int64(endedAt.timeIntervalSince1970 * 1000),
                    date: endedAt,
                    delta: -amount,
                    kind: .withdrawal
                )
            )
        }

        return events.sorted { lhs, rhs in
            if lhs.sortMs != rhs.sortMs { return lhs.sortMs < rhs.sortMs }
            if lhs.kind == rhs.kind { return false }
            return lhs.kind == .trade
        }
    }

    private static func replayTradeLevel(
        startingBalance: Decimal,
        openingBalance: Decimal,
        events: [TimelineEvent],
        hasPeriodWindow: Bool,
        periodStartMs: Int64?,
        periodEndMs: Int64
    ) -> [EquitySample] {
        var points: [EquitySample] = []

        if hasPeriodWindow, let periodStartMs {
            points.append(
                EquitySample(
                    date: Date(timeIntervalSince1970: TimeInterval(periodStartMs) / 1000),
                    equity: openingBalance,
                    drawdownFloor: nil
                )
            )
        }

        if events.isEmpty {
            if hasPeriodWindow {
                points.append(
                    EquitySample(
                        date: Date(timeIntervalSince1970: TimeInterval(periodEndMs) / 1000),
                        equity: openingBalance,
                        drawdownFloor: nil
                    )
                )
            } else if startingBalance > 0 {
                points.append(EquitySample(date: Date(), equity: startingBalance, drawdownFloor: nil))
            }
            return points
        }

        if !hasPeriodWindow {
            points.append(
                EquitySample(date: events[0].date, equity: startingBalance, drawdownFloor: nil)
            )
        }

        var balance = openingBalance
        for event in events {
            balance += event.delta
            points.append(EquitySample(date: event.date, equity: balance, drawdownFloor: nil))
        }
        return points
    }

    private static func collapseToDailyClosing(_ samples: [EquitySample], account: TradingAccount) -> [EquitySample] {
        guard !samples.isEmpty else { return samples }
        var buckets: [(key: String, points: [EquitySample])] = []
        for sample in samples {
            let key = tradingDayKey(for: sample.date, account: account)
            if buckets.last?.key == key {
                buckets[buckets.count - 1].points.append(sample)
            } else {
                buckets.append((key, [sample]))
            }
        }

        var result: [EquitySample] = []
        for bucket in buckets {
            let points = bucket.points
            guard let close = points.last else { continue }
            if points.count == 1 {
                result.append(close)
                continue
            }
            let open = points[0]
            if open.equity != close.equity {
                result.append(open)
            }
            result.append(close)
        }
        return result
    }

    private static func tradingDayKey(for date: Date, account: TradingAccount) -> String {
        if account.isPropFirmAccount, let key = PropFirmTradingDay.key(for: date) {
            return key
        }
        let calendar = Calendar.current
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = comps.year, let m = comps.month, let d = comps.day else {
            return String(Int64(date.timeIntervalSince1970))
        }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    // MARK: - Period (web dashboardLiveAccountValue parity)

    private static func resolvePeriodStartMs(_ period: PeriodContext) -> Int64? {
        if let interval = period.customInterval {
            return Int64(interval.start.timeIntervalSince1970 * 1000)
        }
        let now = period.now
        let calendar = Calendar.current
        let start: Date? = {
            switch period.dateRange {
            case .all: return nil
            case .sevenDays: return calendar.date(byAdding: .day, value: -7, to: now)
            case .thirtyDays: return calendar.date(byAdding: .day, value: -30, to: now)
            case .ninetyDays: return calendar.date(byAdding: .day, value: -90, to: now)
            case .oneYear: return calendar.date(byAdding: .day, value: -365, to: now)
            case .ytd:
                let year = calendar.component(.year, from: now)
                return calendar.date(from: DateComponents(year: year, month: 1, day: 1))
            }
        }()
        guard let start else { return nil }
        return Int64(start.timeIntervalSince1970 * 1000)
    }

    private static func resolvePeriodEndMs(_ period: PeriodContext) -> Int64 {
        if let interval = period.customInterval {
            return Int64(interval.end.timeIntervalSince1970 * 1000)
        }
        return Int64(period.now.timeIntervalSince1970 * 1000)
    }

    private static func tradeIsBeforePeriod(
        _ trade: Trade,
        periodStartMs: Int64?,
        period: PeriodContext
    ) -> Bool {
        guard let periodStartMs else { return false }
        let stamp = DashboardScopeFilterSupport.dashboardTradeFilterDate(for: trade)
        return Int64(stamp.timeIntervalSince1970 * 1000) < periodStartMs
    }

    private static func tradeMatchesPeriod(_ trade: Trade, period: PeriodContext) -> Bool {
        let stamp = DashboardScopeFilterSupport.dashboardTradeFilterDate(for: trade)
        if let interval = period.customInterval {
            return stamp >= interval.start && stamp <= interval.end
        }
        return period.dateRange.contains(stamp, now: period.now)
    }

    private static func withdrawalIsBeforePeriod(
        _ date: Date,
        periodStartMs: Int64?,
        period: PeriodContext
    ) -> Bool {
        guard let periodStartMs else { return false }
        return Int64(date.timeIntervalSince1970 * 1000) < periodStartMs
    }

    private static func withdrawalMatchesPeriod(_ date: Date, period: PeriodContext) -> Bool {
        if let interval = period.customInterval {
            return date >= interval.start && date <= interval.end
        }
        return period.dateRange.contains(date, now: period.now)
    }

    private static func tradeChronological(_ lhs: Trade, _ rhs: Trade) -> Bool {
        let left = DashboardScopeFilterSupport.dashboardTradeFilterDate(for: lhs)
        let right = DashboardScopeFilterSupport.dashboardTradeFilterDate(for: rhs)
        return left < right
    }

    private static func tradeMatchesEnginePolicy(_ trade: Trade, includesBacktestTrades: Bool) -> Bool {
        if includesBacktestTrades {
            return trade.mode == .backtest
        }
        return trade.mode != .backtest
    }
}