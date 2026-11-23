import Foundation

/// Prop firm equity + trailing drawdown floor for the dashboard hero (web personal drawdown parity).
nonisolated enum PropFirmDrawdownEquityEngine {
    struct EquitySample: Sendable, Equatable {
        var date: Date
        var equity: Decimal
        var drawdownFloor: Decimal
    }

    /// Account-balance samples with drawdown floor overlay. Returns `nil` when rules omit max drawdown.
    static func computeEquitySeries(
        account: TradingAccount,
        lifetimeTrades: [Trade],
        payoutCycles: [AccountPayoutCycle],
        period: LivePersonalDrawdownEngine.PeriodContext
    ) -> [EquitySample]? {
        guard account.isPropFirmAccount else { return nil }
        let rules = account.propFirmRules ?? PropFirmAccountRules()
        guard let maxDd = rules.maxDrawdown, maxDd > 0 else { return nil }

        let accountSize = PropFirmMetrics.parseAccountSize(account.size)
        let activeCycle = PropFirmPayoutCycleSupport.selectActivePayoutCycle(payoutCycles)
        let cycleContext = PropFirmPayoutCycleSupport.buildPayoutCycleContext(
            activeCycle: activeCycle,
            accountStartingBalance: accountSize
        )

        let accountTrades = lifetimeTrades.filter { $0.accountID == account.id && $0.mode != .backtest }
        let inputs = PropFirmMetrics.tradeInputs(from: accountTrades)
        let cycleInputs = filterCycleTrades(inputs, startedAt: cycleContext.startedAt)

        let events = buildTimelineEvents(
            trades: cycleInputs,
            payoutCycles: payoutCycles,
            accountID: account.id
        )
        guard !events.isEmpty else {
            let floor = initialDrawdownFloor(
                cycleStartBalance: cycleContext.cycleStartBalance,
                maxDrawdown: maxDd,
                initialFloor: cycleContext.initialDrawdownFloor
            )
            return [
                EquitySample(
                    date: period.now,
                    equity: cycleContext.cycleStartBalance,
                    drawdownFloor: floor
                ),
            ]
        }

        let lockFloor = shouldLockDrawdownFloor(
            drawdownType: rules.drawdownType,
            cycleContext: cycleContext
        )

        let initialFloor = initialDrawdownFloor(
            cycleStartBalance: cycleContext.cycleStartBalance,
            maxDrawdown: maxDd,
            initialFloor: cycleContext.initialDrawdownFloor
        )

        let allSamples = replayEvents(
            events: events,
            startingBalance: cycleContext.cycleStartBalance,
            accountBase: accountSize,
            maxDrawdown: maxDd,
            initialDrawdownFloor: initialFloor,
            drawdownType: rules.drawdownType ?? .intradayTrailing,
            lockFloor: lockFloor
        )

        return sliceForPeriod(allSamples, period: period)
    }

    static func mapToEquityPoints(_ samples: [EquitySample]) -> [ProfileStatisticsMetrics.EquityPoint] {
        samples.enumerated().map { offset, sample in
            ProfileStatisticsMetrics.EquityPoint(
                index: offset,
                equity: sample.equity,
                date: sample.date,
                drawdownFloor: sample.drawdownFloor
            )
        }
    }

    // MARK: - Timeline

    private enum EventKind { case trade, payout }

    private struct TimelineEvent {
        var sortMs: Int64
        var date: Date
        var delta: Decimal
        var kind: EventKind
        var tradingDayKey: String?
        var payoutBehavior: PayoutDrawdownBehavior?
    }

    private struct TrailingSnapshot {
        var balance: Decimal
        var peakBalance: Decimal
        var drawdownFloor: Decimal
    }

    private static func buildTimelineEvents(
        trades: [PropFirmMetrics.TradeInput],
        payoutCycles: [AccountPayoutCycle],
        accountID: TradingAccountID
    ) -> [TimelineEvent] {
        var events: [TimelineEvent] = []

        let sortedTrades = trades.sorted {
            ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
        for trade in sortedTrades {
            let stamp = trade.exitAt ?? trade.entryAt ?? trade.createdAt ?? .distantPast
            events.append(
                TimelineEvent(
                    sortMs: Int64(stamp.timeIntervalSince1970 * 1000),
                    date: stamp,
                    delta: trade.pnl,
                    kind: .trade,
                    tradingDayKey: PropFirmTradingDay.key(for: trade)
                )
            )
        }

        for cycle in payoutCycles where cycle.accountID == accountID {
            guard let endedAt = cycle.endedAt,
                  let amount = cycle.payoutAmount,
                  amount > 0
            else { continue }
            events.append(
                TimelineEvent(
                    sortMs: Int64(endedAt.timeIntervalSince1970 * 1000),
                    date: endedAt,
                    delta: -amount,
                    kind: .payout,
                    tradingDayKey: PropFirmTradingDay.key(for: endedAt),
                    payoutBehavior: cycle.drawdownBehavior
                )
            )
        }

        return events.sorted { lhs, rhs in
            if lhs.sortMs != rhs.sortMs { return lhs.sortMs < rhs.sortMs }
            if lhs.kind == rhs.kind { return false }
            return lhs.kind == .trade
        }
    }

    private static func replayEvents(
        events: [TimelineEvent],
        startingBalance: Decimal,
        accountBase: Decimal,
        maxDrawdown: Decimal,
        initialDrawdownFloor: Decimal,
        drawdownType: PropFirmDrawdownType,
        lockFloor: Bool
    ) -> [EquitySample] {
        guard let anchor = events.first else { return [] }

        var balance = startingBalance
        var peakBalance = startingBalance
        var drawdownFloor = initialDrawdownFloor

        var samples: [EquitySample] = [
            EquitySample(date: anchor.date, equity: balance, drawdownFloor: drawdownFloor),
        ]

        if drawdownType == .endOfDayTrailing {
            var currentDayKey = anchor.tradingDayKey
            var dayHighBalance = balance

            for event in events {
                let balanceBefore = balance
                balance += event.delta

                if event.kind == .payout {
                    let behavior = event.payoutBehavior ?? .keepTrailing
                    let snapshot = TrailingSnapshot(
                        balance: balanceBefore,
                        peakBalance: peakBalance,
                        drawdownFloor: drawdownFloor
                    )
                    (balance, drawdownFloor, peakBalance) = applyPayout(
                        balanceAfter: balance,
                        snapshot: snapshot,
                        behavior: behavior,
                        accountBase: accountBase,
                        maxDrawdown: maxDrawdown
                    )
                } else {
                    let dayKey = event.tradingDayKey
                    if let dayKey, dayKey != currentDayKey {
                        if dayHighBalance > peakBalance, !lockFloor {
                            peakBalance = dayHighBalance
                            drawdownFloor = min(accountBase, peakBalance - maxDrawdown)
                        }
                        currentDayKey = dayKey
                        dayHighBalance = balance
                    } else {
                        dayHighBalance = max(dayHighBalance, balance)
                    }
                }

                samples.append(
                    EquitySample(date: event.date, equity: balance, drawdownFloor: drawdownFloor)
                )
            }
            if let last = events.last,
               last.tradingDayKey != nil,
               dayHighBalance > peakBalance,
               !lockFloor
            {
                peakBalance = dayHighBalance
                drawdownFloor = min(accountBase, peakBalance - maxDrawdown)
                if var final = samples.last, final.date == last.date {
                    final.drawdownFloor = drawdownFloor
                    samples[samples.count - 1] = final
                }
            }
            return samples
        }

        for event in events {
            let balanceBefore = balance
            balance += event.delta

            if event.kind == .payout {
                let behavior = event.payoutBehavior ?? .keepTrailing
                let snapshot = TrailingSnapshot(
                    balance: balanceBefore,
                    peakBalance: peakBalance,
                    drawdownFloor: drawdownFloor
                )
                (balance, drawdownFloor, peakBalance) = applyPayout(
                    balanceAfter: balance,
                    snapshot: snapshot,
                    behavior: behavior,
                    accountBase: accountBase,
                    maxDrawdown: maxDrawdown
                )
            } else if balance > peakBalance {
                peakBalance = balance
                if !lockFloor {
                    drawdownFloor = min(accountBase, peakBalance - maxDrawdown)
                }
            }

            samples.append(
                EquitySample(date: event.date, equity: balance, drawdownFloor: drawdownFloor)
            )
        }
        return samples
    }

    private static func applyPayout(
        balanceAfter: Decimal,
        snapshot: TrailingSnapshot,
        behavior: PayoutDrawdownBehavior,
        accountBase: Decimal,
        maxDrawdown: Decimal
    ) -> (balance: Decimal, floor: Decimal, peak: Decimal) {
        let trailing = PropFirmMetrics.TrailingDrawdownResult(
            currentBalance: snapshot.balance,
            peakBalance: snapshot.peakBalance,
            drawdownFloor: snapshot.drawdownFloor,
            distanceToDD: snapshot.balance - snapshot.drawdownFloor,
            maxDrawdownUsed: 0,
            breachedTrailingDD: false
        )
        let floor = PropFirmMetrics.computePayoutDrawdownFloor(
            behavior: behavior,
            accountBaseBalance: accountBase,
            trailingMetricsBeforePayout: trailing,
            maxDrawdown: maxDrawdown
        )
        if behavior == .resetToAccount {
            return (balanceAfter, floor, balanceAfter)
        }
        return (balanceAfter, floor, snapshot.peakBalance)
    }

    private static func initialDrawdownFloor(
        cycleStartBalance: Decimal,
        maxDrawdown: Decimal,
        initialFloor: Decimal?
    ) -> Decimal {
        if let initialFloor { return initialFloor }
        return cycleStartBalance - maxDrawdown
    }

    private static func shouldLockDrawdownFloor(
        drawdownType: PropFirmDrawdownType?,
        cycleContext: PropFirmMetrics.PayoutCycleContext
    ) -> Bool {
        if drawdownType == .staticThreshold { return true }
        let lockFromPayout = (cycleContext.drawdownBehavior == PayoutDrawdownBehavior.resetToAccount.rawValue)
            && cycleContext.initialDrawdownFloor != nil
        return lockFromPayout
    }

    private static func filterCycleTrades(
        _ trades: [PropFirmMetrics.TradeInput],
        startedAt: Date?
    ) -> [PropFirmMetrics.TradeInput] {
        guard let startedAt else { return trades }
        return trades.filter { trade in
            let stamp = trade.exitAt ?? trade.entryAt ?? trade.createdAt
            guard let stamp else { return false }
            return stamp >= startedAt
        }
    }

    // MARK: - Period window (Live personal drawdown parity)

    private static func sliceForPeriod(
        _ samples: [EquitySample],
        period: LivePersonalDrawdownEngine.PeriodContext
    ) -> [EquitySample] {
        guard let startMs = periodStartMs(period) else { return samples }
        let endMs = periodEndMs(period)
        let filtered = samples.filter {
            let ms = Int64($0.date.timeIntervalSince1970 * 1000)
            return ms >= startMs && ms <= endMs
        }
        guard !filtered.isEmpty else { return samples }
        guard let first = filtered.first else { return filtered }

        let opening = samples.last(where: {
            Int64($0.date.timeIntervalSince1970 * 1000) < startMs
        }) ?? samples.first { Int64($0.date.timeIntervalSince1970 * 1000) <= startMs }
        ?? first

        var points = [EquitySample(date: opening.date, equity: opening.equity, drawdownFloor: opening.drawdownFloor)]
        for sample in filtered where sample.date > opening.date {
            points.append(sample)
        }
        return points
    }

    private static func periodStartMs(_ period: LivePersonalDrawdownEngine.PeriodContext) -> Int64? {
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

    private static func periodEndMs(_ period: LivePersonalDrawdownEngine.PeriodContext) -> Int64 {
        if let interval = period.customInterval {
            return Int64(interval.end.timeIntervalSince1970 * 1000)
        }
        return Int64(period.now.timeIntervalSince1970 * 1000)
    }
}