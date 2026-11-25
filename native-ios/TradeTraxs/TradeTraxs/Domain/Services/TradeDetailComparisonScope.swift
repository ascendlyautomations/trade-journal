import Foundation

/// Filters + normalization for Trade Detail owner comparisons, mirrors trades list scope.
nonisolated enum TradeDetailComparisonScope {
    static func normalizedTicker(_ raw: String) -> String {
        FuturesInstrumentRegistry.normalizeSymbol(raw)
    }

    static func tickersMatch(_ lhs: String, _ rhs: String) -> Bool {
        normalizedTicker(lhs) == normalizedTicker(rhs)
    }

    static func isEligible(_ trade: Trade, accountModes: [TradingAccountID: TradingAccountMode] = [:]) -> Bool {
        if trade.mode == .backtest { return false }
        if trade.accountMode == .backtest { return false }
        if let accountID = trade.accountID, accountModes[accountID] == .backtest { return false }
        return true
    }

    static func uniqueTradesByID(_ trades: [Trade]) -> [Trade] {
        var seen = Set<TradeID>()
        var unique: [Trade] = []
        unique.reserveCapacity(trades.count)
        for trade in trades {
            if seen.insert(trade.id).inserted {
                unique.append(trade)
            }
        }
        return unique
    }

    static func netPnL(for trade: Trade) -> Decimal {
        trade.realizedPnL?.amount ?? 0
    }

    static func previousOwnerTrades(
        history: [Trade],
        currentTrade: Trade,
        accountModes: [TradingAccountID: TradingAccountMode] = [:]
    ) -> [Trade] {
        uniqueTradesByID(history)
            .filter { $0.id != currentTrade.id }
            .filter { $0.ownerProfileID == currentTrade.ownerProfileID }
            .filter { isEligible($0, accountModes: accountModes) }
    }

    static func previousSameTickerTrades(
        history: [Trade],
        currentTrade: Trade,
        accountModes: [TradingAccountID: TradingAccountMode] = [:]
    ) -> [Trade] {
        let root = normalizedTicker(currentTrade.symbol.ticker)
        guard !root.isEmpty else { return [] }
        return previousOwnerTrades(
            history: history,
            currentTrade: currentTrade,
            accountModes: accountModes
        )
        .filter { tickersMatch($0.symbol.ticker, root) }
    }

    static func normalizedSetup(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    static func matchesAccountMode(
        peer: Trade,
        current: Trade,
        accountModes: [TradingAccountID: TradingAccountMode]
    ) -> Bool {
        guard let currentAccountID = current.accountID else { return false }
        guard peer.accountID == currentAccountID else { return false }
        let currentMode = ProfileStatisticsMetrics.resolveAccountMode(trade: current, accountModes: accountModes)
        let peerMode = ProfileStatisticsMetrics.resolveAccountMode(trade: peer, accountModes: accountModes)
        guard let currentMode, let peerMode else { return false }
        return currentMode == peerMode
    }

    static func matchesSetup(peer: Trade, current: Trade) -> Bool {
        guard let setup = normalizedSetup(current.strategy) else { return false }
        return normalizedSetup(peer.strategy) == setup
    }

    static func matchesSession(peer: Trade, current: Trade) -> Bool {
        guard let session = TradingSessionLabel.canonicalLabel(fromStored: current.sessionLabel) else { return false }
        return TradingSessionLabel.canonicalLabel(fromStored: peer.sessionLabel) == session
    }

    static func filterPeers(
        _ peers: [Trade],
        currentTrade: Trade,
        filter: TradeDetailAnalytics.ComparisonFilter,
        accountModes: [TradingAccountID: TradingAccountMode]
    ) -> [Trade] {
        switch filter {
        case .all:
            return peers
        case .accountMode:
            return peers.filter { matchesAccountMode(peer: $0, current: currentTrade, accountModes: accountModes) }
        case .setup:
            return peers.filter { matchesSetup(peer: $0, current: currentTrade) }
        case .session:
            return peers.filter { matchesSession(peer: $0, current: currentTrade) }
        }
    }
}
