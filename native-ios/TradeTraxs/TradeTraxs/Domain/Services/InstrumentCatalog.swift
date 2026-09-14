import Foundation

/// Shared instrument source for Add Trade / Edit Trade — built-ins, customs, and trade history.
@MainActor
enum InstrumentCatalog {
    static func pickerSnapshot(
        for profileID: ProfileID,
        detailCache: DetailPresentationCache
    ) -> InstrumentPickerSnapshot {
        InstrumentPickerSnapshot(
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
        let fromHistory = tradeHistoryTickers(for: profileID, detailCache: detailCache, limit: limit)
        if fromHistory.count >= 4 {
            return fromHistory
        }
        return mergeUnique(
            fromHistory + InstrumentPickerCatalog.defaultMostUsed,
            limit: limit
        )
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

        let sorted = byID.values.sorted {
            ($0.exitAt ?? $0.entryAt) > ($1.exitAt ?? $1.entryAt)
        }

        var seen = Set<String>()
        var result: [String] = []
        for trade in sorted {
            let ticker = UserCustomInstrumentStore.normalize(trade.symbol.ticker)
            guard !ticker.isEmpty else { continue }
            let key = ticker.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(ticker)
            if result.count >= limit { break }
        }
        return result
    }

    private static func mergeUnique(_ symbols: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for symbol in symbols {
            let normalized = UserCustomInstrumentStore.normalize(symbol)
            guard !normalized.isEmpty else { continue }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(normalized)
            if result.count >= limit { break }
        }
        return result
    }
}
