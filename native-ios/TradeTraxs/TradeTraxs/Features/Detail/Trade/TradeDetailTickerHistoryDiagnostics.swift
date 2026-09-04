#if DEBUG
import Foundation

/// Temporary Trade Detail ticker-history investigation — DEBUG builds only.
enum TradeDetailTickerHistoryDiagnostics {
    struct Context: Sendable {
        var trade: Trade
        var profileID: ProfileID
        var dataSource: String
        var rpcPayload: TradeDetailOwnerComparisonBootstrapV1.DataPayload?
        var rpcError: String?
        var rawHistory: [Trade]
        var accountModes: [TradingAccountID: TradingAccountMode]
        var displayedHistory: TradeDetailAnalytics.TickerHistory?
    }

    @MainActor
    static func log(_ context: Context) {
        let trade = context.trade
        let normalizedTicker = TradeDetailComparisonScope.normalizedTicker(trade.symbol.ticker)
        let rawTicker = trade.symbol.ticker.trimmingCharacters(in: .whitespacesAndNewlines)

        print("[tickerHistory] ===== BEGIN \(rawTicker) (\(normalizedTicker)) trade=\(trade.id.rawValue) =====")
        print("[tickerHistory] dataSource=\(context.dataSource)")
        if let rpcError = context.rpcError {
            print("[tickerHistory] rpcError=\(rpcError)")
        }
        if let wire = context.rpcPayload?.ticker_history {
            print("[tickerHistory] rpcWire ticker=\(wire.ticker) previous_trade_count=\(wire.previous_trade_count) total_pnl=\(wire.total_pnl ?? 0) avg_trade_pnl=\(wire.avg_trade_pnl ?? 0) profit_factor=\(wire.profit_factor ?? 0) win_rate=\(wire.win_rate ?? 0)")
        }
        if let displayed = context.displayedHistory {
            print("[tickerHistory] displayedUI ticker=\(displayed.ticker) previousTradeCount=\(displayed.previousTradeCount) totalPnL=\(displayed.totalPnL) avgTradePnL=\(displayed.avgTradePnL ?? 0) profitFactor=\(displayed.profitFactor ?? 0)")
        }

        print("[tickerHistory] normalizedTickerSearch=\(normalizedTicker)")
        print("[tickerHistory] rawHistoryCount=\(context.rawHistory.count) (SessionOwnerTradesStore / repository cache)")

        logDuplicateIDs(in: context.rawHistory)

        let currentIncludedInRaw = context.rawHistory.contains { $0.id == trade.id }
        print("[tickerHistory] currentTradeIncludedInRawHistory=\(currentIncludedInRaw) currentTradeID=\(trade.id.rawValue)")

        let detailTrades = TradeDetailComparisonScope.previousSameTickerTrades(
            history: context.rawHistory,
            currentTrade: trade,
            accountModes: context.accountModes
        )
        let detailIDs = Set(detailTrades.map(\.id))
        print("[tickerHistory] currentTradeIncludedInTickerHistoryAggregate=false (explicitly excluded by scope)")

        logTradeLines(detailTrades, accountModes: context.accountModes, label: "TradeDetailScope")

        let detailTotals = computeTotals(trades: detailTrades)
        logTotals(detailTotals, ticker: normalizedTicker, label: "TradeDetailScope")

        let tradesPageTrades = tradesPageMNQMatches(
            history: context.rawHistory,
            currentTrade: trade,
            searchTerm: normalizedTicker
        )
        let tradesPageIDs = Set(tradesPageTrades.map(\.id))
        logTradeLines(tradesPageTrades, accountModes: context.accountModes, label: "TradesPageSearch")

        let tradesPageTotals = computeTotals(trades: tradesPageTrades)
        logTotals(tradesPageTotals, ticker: normalizedTicker, label: "TradesPageSearch")

        print("[tickerHistory] TradeDetail MNQ count = \(detailTrades.count)")
        print("[tickerHistory] TradesPage MNQ count = \(tradesPageTrades.count)")
        print("[tickerHistory] TradeDetail MNQ PnL = \(formatDecimal(detailTotals.netPnL))")
        print("[tickerHistory] TradesPage MNQ PnL = \(formatDecimal(tradesPageTotals.netPnL))")

        let onlyInTickerHistory = detailIDs.subtracting(tradesPageIDs).map(\.rawValue).sorted()
        let onlyInTradesPage = tradesPageIDs.subtracting(detailIDs).map(\.rawValue).sorted()
        print("[tickerHistory] onlyInTickerHistory=\(onlyInTickerHistory)")
        print("[tickerHistory] onlyInTradesPage=\(onlyInTradesPage)")

        if !onlyInTickerHistory.isEmpty {
            print("[tickerHistory] --- trades only in TradeDetail scope ---")
            logTradeLines(
                detailTrades.filter { onlyInTickerHistory.contains($0.id.rawValue) },
                accountModes: context.accountModes,
                label: "onlyInTickerHistory"
            )
        }
        if !onlyInTradesPage.isEmpty {
            print("[tickerHistory] --- trades only in TradesPage search ---")
            logTradeLines(
                tradesPageTrades.filter { onlyInTradesPage.contains($0.id.rawValue) },
                accountModes: context.accountModes,
                label: "onlyInTradesPage"
            )
        }

        logIneligibleSameTickerRawRows(
            history: context.rawHistory,
            currentTrade: trade,
            normalizedTicker: normalizedTicker,
            accountModes: context.accountModes,
            includedIDs: detailIDs
        )

        print("[tickerHistory] ===== END \(normalizedTicker) =====")
    }

    // MARK: - Trades page parity

    /// Trades tab MNQ search — `localizedCaseInsensitiveContains` on raw ticker (not normalized root match).
    private static func tradesPageMNQMatches(
        history: [Trade],
        currentTrade: Trade,
        searchTerm: String
    ) -> [Trade] {
        let query = TradeHistoryQuery(searchText: searchTerm)
        return TradeDetailComparisonScope.uniqueTradesByID(history)
            .filter { $0.id != currentTrade.id }
            .filter { $0.ownerProfileID == currentTrade.ownerProfileID }
            .filter { TradeHistoryLocalMatch.matches($0, query: query) }
    }

    // MARK: - Totals

    private struct Totals {
        var includedTrades: Int
        var winningTrades: Int
        var losingTrades: Int
        var breakevenTrades: Int
        var grossWins: Decimal
        var grossLosses: Decimal
        var netPnL: Decimal
        var averageTrade: Decimal?
        var profitFactor: Decimal?
    }

    private static func computeTotals(trades: [Trade]) -> Totals {
        let pnls = trades.map(TradeDetailComparisonScope.netPnL)
        let wins = pnls.filter { $0 > 0 }.count
        let losses = pnls.filter { $0 < 0 }.count
        let breakeven = pnls.filter { $0 == 0 }.count
        let grossWins = pnls.filter { $0 > 0 }.reduce(0, +)
        let grossLosses = pnls.filter { $0 < 0 }.reduce(0, +)
        let netPnL = pnls.reduce(0, +)
        let avg: Decimal? = trades.isEmpty ? nil : netPnL / Decimal(trades.count)
        let pf: Decimal? = grossLosses < 0 ? grossWins / abs(grossLosses) : nil
        return Totals(
            includedTrades: trades.count,
            winningTrades: wins,
            losingTrades: losses,
            breakevenTrades: breakeven,
            grossWins: grossWins,
            grossLosses: grossLosses,
            netPnL: netPnL,
            averageTrade: avg,
            profitFactor: pf
        )
    }

    private static func logTotals(_ totals: Totals, ticker: String, label: String) {
        print("[tickerHistory] --- totals \(label) ---")
        print("[tickerHistory] ticker=\(ticker)")
        print("[tickerHistory] includedTrades=\(totals.includedTrades)")
        print("[tickerHistory] winningTrades=\(totals.winningTrades)")
        print("[tickerHistory] losingTrades=\(totals.losingTrades)")
        print("[tickerHistory] breakevenTrades=\(totals.breakevenTrades)")
        print("[tickerHistory] grossWins=\(formatDecimal(totals.grossWins))")
        print("[tickerHistory] grossLosses=\(formatDecimal(totals.grossLosses))")
        print("[tickerHistory] NET_PNL=\(formatDecimal(totals.netPnL))")
        print("[tickerHistory] averageTrade=\(totals.averageTrade.map(formatDecimal) ?? "—")")
        print("[tickerHistory] profitFactor=\(totals.profitFactor.map { String(format: "%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "—")")
        print("[tickerHistory] SUM(stored pnl)=\(formatDecimal(totals.netPnL))")
    }

    // MARK: - Per-trade lines

    private static func logTradeLines(
        _ trades: [Trade],
        accountModes: [TradingAccountID: TradingAccountMode],
        label: String
    ) {
        print("[tickerHistory] --- trades \(label) count=\(trades.count) ---")
        for row in trades.sorted(by: { $0.entryAt < $1.entryAt }) {
            print(formatTradeLine(row, accountModes: accountModes))
        }
    }

    private static func formatTradeLine(
        _ trade: Trade,
        accountModes: [TradingAccountID: TradingAccountMode]
    ) -> String {
        let pnl = TradeDetailComparisonScope.netPnL(for: trade)
        let accountID = trade.accountID?.rawValue ?? "—"
        let accountMode = resolvedAccountMode(trade, accountModes: accountModes)
        let points = trade.points.map { String(describing: $0) } ?? "—"
        let qty = TradeDisplay.contractsText(trade.quantity)
        let tradeMode = trade.mode.rawValue
        let importSource = trade.importSource?.rawValue ?? "—"
        let entry = TradeDisplay.dateTimeText(trade.entryAt)
        let exit = trade.exitAt.map(TradeDisplay.dateTimeText) ?? "—"
        let date = TradeDisplay.dateText(trade.entryAt)
        let normalized = TradeDetailComparisonScope.normalizedTicker(trade.symbol.ticker)

        return """
        [tickerHistory] id=\(trade.id.rawValue) ticker=\(trade.symbol.ticker) normalized=\(normalized) pnl=\(formatDecimal(pnl)) account=\(accountID) accountMode=\(accountMode) tradeMode=\(tradeMode) date=\(date) entry=\(entry) exit=\(exit) points=\(points) qty=\(qty) import=\(importSource)
        """
    }

    private static func resolvedAccountMode(
        _ trade: Trade,
        accountModes: [TradingAccountID: TradingAccountMode]
    ) -> String {
        if let accountID = trade.accountID, let mode = accountModes[accountID] {
            return mode.rawValue
        }
        if let mode = trade.accountMode {
            return mode.rawValue
        }
        return "—"
    }

    // MARK: - Duplicates / excluded rows

    private static func logDuplicateIDs(in history: [Trade]) {
        var counts: [TradeID: Int] = [:]
        for trade in history {
            counts[trade.id, default: 0] += 1
        }
        let duplicates = counts.filter { $0.value > 1 }.map(\.key.rawValue).sorted()
        if duplicates.isEmpty {
            print("[tickerHistory] duplicateTradeIDs=[]")
        } else {
            print("[tickerHistory] duplicateTradeIDs=\(duplicates)")
            for id in duplicates {
                let dupes = history.filter { $0.id.rawValue == id }
                print("[tickerHistory] duplicate id=\(id) occurrences=\(dupes.count)")
            }
        }
    }

    private static func logIneligibleSameTickerRawRows(
        history: [Trade],
        currentTrade: Trade,
        normalizedTicker: String,
        accountModes: [TradingAccountID: TradingAccountMode],
        includedIDs: Set<TradeID>
    ) {
        let rawSameTicker = TradeDetailComparisonScope.uniqueTradesByID(history)
            .filter { $0.id != currentTrade.id }
            .filter { TradeDetailComparisonScope.tickersMatch($0.symbol.ticker, normalizedTicker) }

        let excluded = rawSameTicker.filter { !includedIDs.contains($0.id) }
        guard !excluded.isEmpty else { return }

        print("[tickerHistory] --- same-ticker rows EXCLUDED from TradeDetail scope count=\(excluded.count) ---")
        for row in excluded {
            var reasons: [String] = []
            if row.ownerProfileID != currentTrade.ownerProfileID {
                reasons.append("ownerMismatch")
            }
            if row.mode == .backtest {
                reasons.append("tradeMode=backtest")
            }
            if row.accountMode == .backtest {
                reasons.append("tradeAccountMode=backtest")
            }
            if let accountID = row.accountID, accountModes[accountID] == .backtest {
                reasons.append("linkedAccountMode=backtest")
            }
            if !TradeDetailComparisonScope.isEligible(row, accountModes: accountModes) {
                reasons.append("isEligible=false")
            }
            print("\(formatTradeLine(row, accountModes: accountModes)) excludedReasons=\(reasons.joined(separator: ","))")
        }
    }

    private nonisolated static func formatDecimal(_ value: Decimal) -> String {
        TradeDisplay.pnlText(Money(amount: value))
    }
}
#endif
