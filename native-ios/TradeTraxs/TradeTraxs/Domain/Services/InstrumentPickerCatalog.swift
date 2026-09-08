import Foundation

/// Built-in instrument lists for the shared Add/Edit Trade picker — display only.
///
/// P&L math remains in ``FuturesInstrumentRegistry`` for symbols with known specs.
/// Web has no separate catalog; native provides quick picks while still storing `trades.ticker`.
nonisolated enum InstrumentPickerCatalog {
    static let defaultMostUsed = ["NQ", "MNQ", "ES", "MES"]

    static let futures: [String] = [
        "ES", "MES", "NQ", "MNQ", "YM", "MYM", "RTY", "M2K",
        "CL", "MCL", "NG",
        "GC", "MGC", "SI",
        "ZB", "ZN", "ZF", "ZT",
        "6E", "6J", "6B", "6A", "6C",
    ]

    static let stocks: [String] = [
        "SPY", "QQQ", "IWM", "DIA",
        "AAPL", "TSLA", "NVDA", "MSFT", "AMZN", "META", "GOOGL", "AMD",
    ]

    static let options: [String] = [
        "SPX", "SPY", "QQQ", "IWM",
    ]

    static let crypto: [String] = [
        "BTC", "ETH", "SOL", "XRP",
    ]

    static let forex: [String] = [
        "EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "USDCHF",
    ]
}

nonisolated struct InstrumentPickerSnapshot: Equatable, Sendable {
    var mostUsed: [String]
    var custom: [String]
    var futures: [String]
    var stocks: [String]
    var options: [String]
    var crypto: [String]
    var forex: [String]

    static let empty = InstrumentPickerSnapshot(
        mostUsed: [],
        custom: [],
        futures: [],
        stocks: [],
        options: [],
        crypto: [],
        forex: []
    )

    func filtering(matching query: String) -> InstrumentPickerSnapshot {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !q.isEmpty else { return self }
        func filter(_ symbols: [String]) -> [String] {
            symbols.filter { $0.uppercased().contains(q) }
        }
        return InstrumentPickerSnapshot(
            mostUsed: filter(mostUsed),
            custom: filter(custom),
            futures: filter(futures),
            stocks: filter(stocks),
            options: filter(options),
            crypto: filter(crypto),
            forex: filter(forex)
        )
    }

    var hasVisibleSymbols: Bool {
        !mostUsed.isEmpty
            || !custom.isEmpty
            || !futures.isEmpty
            || !stocks.isEmpty
            || !options.isEmpty
            || !crypto.isEmpty
            || !forex.isEmpty
    }
}
