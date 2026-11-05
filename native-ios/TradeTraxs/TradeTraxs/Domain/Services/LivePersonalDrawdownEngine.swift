import Foundation

/// Mirrors `lib/livePersonalDrawdown.ts` + withdrawal note parsing from `lib/livePersonalDrawdownNote.ts`.
nonisolated enum LivePersonalDrawdownEngine {
    private static let resetNotePrefix = "[[tt:dd=reset]]"
    private static let keepNotePrefix = "[[tt:dd=keep]]"

    // MARK: - Account config (web parse / gear read)

    static func config(from account: TradingAccount) -> LivePersonalDrawdownConfig? {
        guard PropFirmPayoutPolicy.supportsLiveWithdrawal(for: account) else { return nil }
        guard let stored = account.livePersonalDrawdown,
              let limit = stored.limitAmount,
              limit > 0
        else { return nil }
        return LivePersonalDrawdownConfig(limitAmount: limit, limitType: stored.limitType)
    }

    static func stored(maxDrawdown: Decimal?, drawdownTypeRaw: String?) -> LivePersonalDrawdownStored {
        let limitType = mapDrawdownType(drawdownTypeRaw) ?? .fixed
        let limit: Decimal? = {
            guard let maxDrawdown, maxDrawdown > 0 else { return nil }
            return maxDrawdown
        }()
        return LivePersonalDrawdownStored(limitAmount: limit, limitType: limitType)
    }

    static func gearDraft(from account: TradingAccount) -> (limitDigits: String, limitType: LivePersonalDrawdownType) {
        guard PropFirmPayoutPolicy.supportsLiveWithdrawal(for: account) else {
            return ("", .fixed)
        }
        let stored = account.livePersonalDrawdown ?? LivePersonalDrawdownStored(limitAmount: nil, limitType: .fixed)
        let digits: String = {
            guard let limit = stored.limitAmount, limit > 0 else { return "" }
            return NSDecimalNumber(decimal: limit).stringValue
        }()
        return (digits, stored.limitType)
    }

    static func buildAccountUpdate(config: LivePersonalDrawdownConfig?) -> (maxDrawdown: Double?, drawdownType: String?) {
        guard let config, config.limitAmount > 0 else {
            return (nil, nil)
        }
        let typeRaw = config.limitType == .fixed ? "static" : "end_of_day_trailing"
        return (NSDecimalNumber(decimal: config.limitAmount).doubleValue, typeRaw)
    }

    // MARK: - Equity series

    struct PeriodContext: Sendable {
        var dateRange: DashboardDateRange
        var customInterval: DateInterval?
        var now: Date = Date()
    }

    static func computeEquitySeries(
        account: TradingAccount,
        config: LivePersonalDrawdownConfig,
        lifetimeTrades: [Trade],
        ledgerEntries: [AccountPayoutEntry],
        period: PeriodContext
    ) -> [LivePersonalDrawdownEquitySample] {
        let startingBalance = PropFirmMetrics.parseAccountSize(account.size)
        let accountID = account.id
        let allEvents = buildLifetimeTimeline(
            accountID: accountID,
            lifetimeTrades: lifetimeTrades,
            ledgerEntries: ledgerEntries
        )

        let periodStartMs = resolvePeriodStartMs(period)
        let periodEndMs = resolvePeriodEndMs(period)
        let hasPeriodWindow = periodStartMs != nil

        if !hasPeriodWindow {
            return replayFullSeries(
                events: allEvents,
                startingBalance: startingBalance,
                config: config
            )
        }

        let opening = replayTimelineUntil(
            events: allEvents,
            startingBalance: startingBalance,
            config: config,
            stopBeforeMs: periodStartMs ?? periodEndMs
        )

        let cutoffMs = periodStartMs ?? periodEndMs
        let inPeriod = allEvents.filter { event in
            guard event.sortMs >= cutoffMs else { return false }
            switch event.kind {
            case .trade:
                guard let trade = event.trade else { return false }
                return tradeMatchesPeriod(trade, period: period)
            case .withdrawal:
                guard let payoutDate = event.payoutDate else { return false }
                return withdrawalMatchesPeriod(payoutDate: payoutDate, period: period)
            }
        }

        var points: [LivePersonalDrawdownEquitySample] = [
            LivePersonalDrawdownEquitySample(
                date: Date(timeIntervalSince1970: TimeInterval(cutoffMs) / 1000),
                equity: opening.equity,
                drawdownFloor: floorForState(opening.state, config: config)
            ),
        ]

        var equity = opening.equity
        var state = opening.state
        for event in inPeriod {
            equity += event.delta
            state = applyEventToDrawdownState(state, config: config, equity: equity, event: event)
            points.append(
                LivePersonalDrawdownEquitySample(
                    date: event.date,
                    equity: equity,
                    drawdownFloor: floorForState(state, config: config)
                )
            )
        }
        return points
    }

    static func mapToEquityPoints(_ samples: [LivePersonalDrawdownEquitySample]) -> [ProfileStatisticsMetrics.EquityPoint] {
        samples.enumerated().map { offset, sample in
            ProfileStatisticsMetrics.EquityPoint(
                index: offset,
                equity: sample.equity,
                date: sample.date,
                drawdownFloor: sample.drawdownFloor
            )
        }
    }

    // MARK: - Note parsing

    static func parseWithdrawalBehavior(note: String?) -> LiveWithdrawalDrawdownBehavior? {
        let n = note ?? ""
        if n.hasPrefix(resetNotePrefix) { return .resetToAccount }
        if n.hasPrefix(keepNotePrefix) { return .keepTrailing }
        return nil
    }

    // MARK: - Private

    private enum EventKind { case trade, withdrawal }

    private struct TimelineEvent {
        var sortMs: Int64
        var date: Date
        var delta: Decimal
        var kind: EventKind
        var trade: Trade?
        var payoutDate: Date?
        var withdrawalBehavior: LiveWithdrawalDrawdownBehavior?
    }

    private struct DrawdownState {
        var baseline: Decimal
        var highWaterMark: Decimal
        var trailingFloor: Decimal
    }

    private static func mapDrawdownType(_ raw: String?) -> LivePersonalDrawdownType? {
        let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if t == "static" { return .fixed }
        if t == "trailing" || t == "end_of_day_trailing" || t == "intraday_trailing" {
            return .trailing
        }
        return nil
    }

    private static func buildLifetimeTimeline(
        accountID: TradingAccountID,
        lifetimeTrades: [Trade],
        ledgerEntries: [AccountPayoutEntry]
    ) -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        for trade in lifetimeTrades where trade.accountID == accountID && trade.mode != TradeMode.backtest {
            let sortMs = Int64(trade.entryAt.timeIntervalSince1970 * 1000)
            events.append(
                TimelineEvent(
                    sortMs: sortMs,
                    date: trade.entryAt,
                    delta: trade.realizedPnL?.amount ?? 0,
                    kind: .trade,
                    trade: trade,
                    payoutDate: nil,
                    withdrawalBehavior: nil
                )
            )
        }
        for entry in ledgerEntries where entry.accountID == accountID {
            let sortMs = Int64(noonMs(for: entry.payoutDate))
            events.append(
                TimelineEvent(
                    sortMs: sortMs,
                    date: entry.payoutDate,
                    delta: -(entry.amount.amount),
                    kind: .withdrawal,
                    trade: nil,
                    payoutDate: entry.payoutDate,
                    withdrawalBehavior: parseWithdrawalBehavior(note: entry.note) ?? .resetToAccount
                )
            )
        }
        events.sort { lhs, rhs in
            if lhs.sortMs != rhs.sortMs { return lhs.sortMs < rhs.sortMs }
            if lhs.kind == rhs.kind { return false }
            return lhs.kind == .trade
        }
        return events
    }

    private static func replayFullSeries(
        events: [TimelineEvent],
        startingBalance: Decimal,
        config: LivePersonalDrawdownConfig
    ) -> [LivePersonalDrawdownEquitySample] {
        if events.isEmpty {
            let state = initialState(startingBalance: startingBalance, config: config)
            return [
                LivePersonalDrawdownEquitySample(
                    date: Date(),
                    equity: startingBalance,
                    drawdownFloor: floorForState(state, config: config)
                ),
            ]
        }

        var points: [LivePersonalDrawdownEquitySample] = []
        var equity = startingBalance
        var state = initialState(startingBalance: startingBalance, config: config)
        points.append(
            LivePersonalDrawdownEquitySample(
                date: events[0].date,
                equity: startingBalance,
                drawdownFloor: floorForState(state, config: config)
            )
        )
        for event in events {
            equity += event.delta
            state = applyEventToDrawdownState(state, config: config, equity: equity, event: event)
            points.append(
                LivePersonalDrawdownEquitySample(
                    date: event.date,
                    equity: equity,
                    drawdownFloor: floorForState(state, config: config)
                )
            )
        }
        return points
    }

    private static func replayTimelineUntil(
        events: [TimelineEvent],
        startingBalance: Decimal,
        config: LivePersonalDrawdownConfig,
        stopBeforeMs: Int64
    ) -> (equity: Decimal, state: DrawdownState) {
        var equity = startingBalance
        var state = initialState(startingBalance: startingBalance, config: config)
        for event in events {
            if event.sortMs >= stopBeforeMs { break }
            equity += event.delta
            state = applyEventToDrawdownState(state, config: config, equity: equity, event: event)
        }
        return (equity, state)
    }

    private static func initialState(startingBalance: Decimal, config: LivePersonalDrawdownConfig) -> DrawdownState {
        DrawdownState(
            baseline: startingBalance,
            highWaterMark: startingBalance,
            trailingFloor: startingBalance - config.limitAmount
        )
    }

    private static func floorForState(_ state: DrawdownState, config: LivePersonalDrawdownConfig) -> Decimal {
        config.limitType == .fixed ? state.baseline - config.limitAmount : state.trailingFloor
    }

    private static func applyEventToDrawdownState(
        _ state: DrawdownState,
        config: LivePersonalDrawdownConfig,
        equity: Decimal,
        event: TimelineEvent
    ) -> DrawdownState {
        if event.kind == .withdrawal {
            return applyWithdrawalRules(
                state,
                config: config,
                equityAfterWithdrawal: equity,
                behavior: event.withdrawalBehavior ?? .resetToAccount
            )
        }
        if config.limitType == .fixed { return state }
        let highWaterMark = max(state.highWaterMark, equity)
        let candidate = highWaterMark - config.limitAmount
        return DrawdownState(
            baseline: state.baseline,
            highWaterMark: highWaterMark,
            trailingFloor: max(state.trailingFloor, candidate)
        )
    }

    private static func applyWithdrawalRules(
        _ state: DrawdownState,
        config: LivePersonalDrawdownConfig,
        equityAfterWithdrawal: Decimal,
        behavior: LiveWithdrawalDrawdownBehavior
    ) -> DrawdownState {
        guard behavior == .resetToAccount else { return state }
        return DrawdownState(
            baseline: equityAfterWithdrawal,
            highWaterMark: equityAfterWithdrawal,
            trailingFloor: equityAfterWithdrawal - config.limitAmount
        )
    }

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

    private static func tradeMatchesPeriod(_ trade: Trade, period: PeriodContext) -> Bool {
        if let interval = period.customInterval {
            return trade.entryAt >= interval.start && trade.entryAt <= interval.end
        }
        return period.dateRange.contains(trade.entryAt, now: period.now)
    }

    private static func withdrawalMatchesPeriod(payoutDate: Date, period: PeriodContext) -> Bool {
        if let interval = period.customInterval {
            return payoutDate >= interval.start && payoutDate <= interval.end
        }
        return period.dateRange.contains(payoutDate, now: period.now)
    }

    private static func noonMs(for date: Date) -> Int64 {
        var calendar = Calendar.current
        calendar.timeZone = .gmt
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let noon = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: comps.day, hour: 12)) ?? date
        return Int64(noon.timeIntervalSince1970 * 1000)
    }
}
