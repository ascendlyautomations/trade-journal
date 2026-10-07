import Foundation

/// Shared instrument source for Add Trade / Edit Trade — built-ins, customs, and trade history.
@MainActor
enum InstrumentCatalog {
    static func pickerSnapshot(
        for profileID: ProfileID,
        detailCache: DetailPresentationCache
    ) -> InstrumentPickerSnapshot {
        SessionOwnerTradesStore.shared.hydrateFromDiskIfNeeded(
            for: profileID,
            detailCache: detailCache
        )
        return InstrumentPickerSnapshot(
            mostUsed: mostUsedSymbols(for: profileID, detailCache: detailCache),
            custom: UserCustomInstrumentStore.shared.customSymbols(for: profileID),
            futures: InstrumentPickerCatalog.futures,
            stocks: InstrumentPickerCatalog.stocks,
            options: InstrumentPickerCatalog.options,
            crypto: InstrumentPickerCatalog.crypto,
            forex: InstrumentPickerCatalog.forex
        )
    }

    static func mostUsedSymbols(
        for profileID: ProfileID,
        detailCache: DetailPresentationCache,
        limit: Int = 8
    ) -> [String] {
        tradeHistoryTickers(for: profileID, detailCache: detailCache, limit: limit)
    }

    @discardableResult
    static func registerCustom(_ symbol: String, for profileID: ProfileID) -> String? {
        UserCustomInstrumentStore.shared.add(symbol, for: profileID)
    }

    static func removeCustom(_ symbol: String, for profileID: ProfileID) {
        UserCustomInstrumentStore.shared.remove(symbol, for: profileID)
    }

    static func tradeHistoryTickers(
        for profileID: ProfileID,
        detailCache: DetailPresentationCache,
        limit: Int
    ) -> [String] {
        var byID: [TradeID: Trade] = [:]

        if let cached = SessionOwnerTradesStore.shared.cached(for: profileID) {
            for trade in cached {
                byID[trade.id] = trade
            }
        }

        if let disk = SessionDiskCache.loadOwnerTrades(
            for: profileID,
            maxAge: 30 * 24 * 60 * 60
        ) {
            for trade in disk.trades {
                byID[trade.id] = trade
            }
        }

        for trade in detailCache.tradesOwnedBy(profileID) {
            byID[trade.id] = trade
        }

        struct TickerUsage {
            var ticker: String
            var count: Int
            var lastUsed: Date
        }

        var usageByKey: [String: TickerUsage] = [:]
        for trade in byID.values {
            let ticker = UserCustomInstrumentStore.normalize(trade.symbol.ticker)
            guard !ticker.isEmpty else { continue }
            let key = ticker.lowercased()
            let usedAt = trade.exitAt ?? trade.entryAt
            if var existing = usageByKey[key] {
                existing.count += 1
                if usedAt > existing.lastUsed {
                    existing.lastUsed = usedAt
                }
                usageByKey[key] = existing
            } else {
                usageByKey[key] = TickerUsage(ticker: ticker, count: 1, lastUsed: usedAt)
            }
        }

        return usageByKey.values
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.lastUsed > $1.lastUsed
            }
            .prefix(limit)
            .map(\.ticker)
    }
}
