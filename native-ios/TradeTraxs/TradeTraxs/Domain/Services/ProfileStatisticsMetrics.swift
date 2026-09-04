import Foundation

/// Mirrors web `useProfileStatistics` + `ProfileStatisticsTab` analytics formulas.
///
/// Mode filter uses authoritative ``TradingAccountMode`` only — from linked
/// `accounts.mode` (profile bootstrap) or denormalized trade `account_type` / `mode`.
/// Backtest rows are excluded from All / Eval / Funded / Live / Sim — same as web.
nonisolated enum ProfileStatisticsMetrics {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        case all
        case eval
        case funded
        case live
        case sim
        case backtest

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .eval: return "Eval"
            case .funded: return "Funded"
            case .live: return "Live"
            case .sim: return "Sim"
            case .backtest: return "Backtest"
            }
        }

        var tradingAccountMode: TradingAccountMode? {
            switch self {
            case .all: return nil
            case .eval: return .evaluation
            case .funded: return .funded
            case .live: return .live
            case .sim: return .sim
            case .backtest: return .backtest
            }
        }

        /// Profile Statistics filter chips — Sim/Backtest remain valid modes elsewhere.
        static let profileFilterCases: [Mode] = [.all, .live, .funded, .eval]
    }

    struct TradeInput: Sendable, Equatable {
        var pnl: Decimal?
        var createdAt: Date?
        var isLong: Bool
        var session: String?
        /// Authoritative account mode for this trade.
        var accountMode: TradingAccountMode?
    }

    struct EquityPoint: Sendable, Equatable, Identifiable {
        var index: Int
        var equity: Decimal
        /// Trade timestamp when available — presentation only (does not affect equity math).
        var date: Date? = nil
        var id: Int { index }
    }

    struct SessionRow: Sendable, Equatable, Identifiable {
        var label: String
        var count: Int
        var pct: Double
        var id: String { label }
    }

    struct Result: Sendable, Equatable {
        var filteredTradeCount: Int
        /// Win rate as `0...1` for Stats presentation (same wins ÷ trades as web).
        var winRate: Decimal?
        var profitFactor: Decimal?
        var averageWinner: Decimal?
        var averageLoser: Decimal?
        var profitPerTrade: Decimal?
        var biggestWin: Decimal
        var biggestLoss: Decimal?
        var longTrades: Int
        var maxWinStreak: Int
        var maxLossStreak: Int
        var sessionTotal: Int
        var sessionBreakdown: [SessionRow]
        var currentEquity: Decimal
        var equityData: [EquityPoint]
    }

    /// Resolve authoritative account mode: linked account map wins, then trade denormalization.
    static func resolveAccountMode(
        trade: Trade,
        accountModes: [TradingAccountID: TradingAccountMode]
    ) -> TradingAccountMode? {
        if let accountID = trade.accountID, let authoritative = accountModes[accountID] {
            return authoritative
        }
        return trade.accountMode
    }

    static func tradeInput(
        from trade: Trade,
        accountModes: [TradingAccountID: TradingAccountMode]
    ) -> TradeInput {
        TradeInput(
            pnl: trade.realizedPnL?.amount,
            createdAt: trade.createdAt,
            isLong: trade.side == .long,
            session: trade.sessionLabel,
            accountMode: resolveAccountMode(trade: trade, accountModes: accountModes)
        )
    }

    static func compute(from trades: [TradeInput], selectedMode: Mode) -> Result {
        let filtered = trades.filter { matchesMode($0, selectedMode) }
        let analytics = selectedMode == .backtest ? filtered : excludingBacktest(filtered)

        let totalTrades = analytics.count
        let wins = analytics.filter { ($0.pnl ?? 0) > 0 }.count
        let totalPnl = analytics.reduce(Decimal(0)) { $0 + ($1.pnl ?? 0) }

        let biggestWin: Decimal = analytics.isEmpty
            ? 0
            : analytics.map { $0.pnl ?? 0 }.max() ?? 0
        let losingPnls = analytics.map { $0.pnl ?? 0 }.filter { $0 < 0 }
        let biggestLoss: Decimal? = losingPnls.isEmpty ? nil : losingPnls.min()
        let longTrades = analytics.filter(\.isLong).count

        // Web builds equity from newest→oldest reversed to chronological order.
        let equityData: [EquityPoint] = {
            let chronological = analytics.reversed()
            var points: [EquityPoint] = []
            var running = Decimal(0)
            for (index, trade) in chronological.enumerated() {
                running += trade.pnl ?? 0
                points.append(
                    EquityPoint(index: index, equity: running, date: trade.createdAt)
                )
            }
            return points
        }()
        let currentEquity = equityData.last?.equity ?? 0

        let grossWins = analytics.reduce(Decimal(0)) { sum, trade in
            let pnl = trade.pnl ?? 0
            return pnl > 0 ? sum + pnl : sum
        }
        let grossLosses = analytics.reduce(Decimal(0)) { sum, trade in
            let pnl = trade.pnl ?? 0
            return pnl < 0 ? sum + pnl : sum
        }
        let profitFactor: Decimal? = grossLosses < 0
            ? grossWins / abs(grossLosses)
            : nil
        let averageWinner: Decimal? = wins > 0 ? grossWins / Decimal(wins) : nil
        let lossCount = analytics.filter { ($0.pnl ?? 0) < 0 }.count
        let averageLoser: Decimal? = lossCount > 0 ? grossLosses / Decimal(lossCount) : nil
        let profitPerTrade: Decimal? = totalTrades > 0 ? totalPnl / Decimal(totalTrades) : nil
        let winRate: Decimal? = totalTrades > 0 ? Decimal(wins) / Decimal(totalTrades) : nil

        let streaks = maxStreaks(analytics)
        let sessions = sessionBreakdown(analytics)

        return Result(
            filteredTradeCount: totalTrades,
            winRate: winRate,
            profitFactor: profitFactor,
            averageWinner: averageWinner,
            averageLoser: averageLoser,
            profitPerTrade: profitPerTrade,
            biggestWin: biggestWin,
            biggestLoss: biggestLoss,
            longTrades: longTrades,
            maxWinStreak: streaks.win,
            maxLossStreak: streaks.loss,
            sessionTotal: sessions.total,
            sessionBreakdown: sessions.rows,
            currentEquity: currentEquity,
            equityData: equityData
        )
    }

    // MARK: - Filters

    static func excludingBacktest(_ trades: [TradeInput]) -> [TradeInput] {
        trades.filter { $0.accountMode != .backtest }
    }

    static func matchesMode(_ trade: TradeInput, _ selected: Mode) -> Bool {
        if selected == .all { return true }
        guard let target = selected.tradingAccountMode else { return true }
        return trade.accountMode == target
    }

    /// Map `TradingAccountMode` → web filter / account_type string.
    static func accountTypeString(for mode: TradingAccountMode) -> String {
        switch mode {
        case .evaluation: return "eval"
        case .funded: return "funded"
        case .live: return "live"
        case .sim: return "sim"
        case .backtest: return "backtest"
        }
    }

    // MARK: - Private

    private static func maxStreaks(_ trades: [TradeInput]) -> (win: Int, loss: Int) {
        let ordered = trades.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        var currentWin = 0
        var currentLoss = 0
        var maxWin = 0
        var maxLoss = 0
        for trade in ordered {
            let pnl = trade.pnl ?? 0
            if pnl > 0 {
                currentWin += 1
                currentLoss = 0
            } else if pnl < 0 {
                currentLoss += 1
                currentWin = 0
            } else {
                currentWin = 0
                currentLoss = 0
            }
            if currentWin > maxWin { maxWin = currentWin }
            if currentLoss > maxLoss { maxLoss = currentLoss }
        }
        return (maxWin, maxLoss)
    }

    private static func sessionBreakdown(_ trades: [TradeInput]) -> (total: Int, rows: [SessionRow]) {
        var counts: [String: Int] = [:]
        for trade in trades {
            let raw = (trade.session ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let label: String?
            if raw.contains("ny") || raw.contains("new york") {
                label = "NY"
            } else if raw.contains("london") || raw.contains("ldn") || raw.contains("uk") {
                label = "London"
            } else if raw.contains("asia") || raw.contains("asian") || raw.contains("tokyo") {
                label = "Asia"
            } else {
                label = nil
            }
            if let label {
                counts[label, default: 0] += 1
            }
        }
        let total = counts.values.reduce(0, +)
        let rows = ["NY", "London", "Asia"].compactMap { label -> SessionRow? in
            let count = counts[label] ?? 0
            guard count > 0 else { return nil }
            let pct = total > 0 ? (Double(count) / Double(total)) * 100 : 0
            return SessionRow(label: label, count: count, pct: pct)
        }
        return (total, rows)
    }
}
