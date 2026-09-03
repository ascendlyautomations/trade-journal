import Foundation

/// Platform-specific screenshot layout strategy.
nonisolated protocol ScreenshotTradePlatformAdapter: Sendable {
    var platform: ScreenshotImportPlatform { get }
    func detect(in rows: [ScreenshotTableRow]) -> Bool
    func parseFills(from rows: [ScreenshotTableRow]) -> [ParsedTradeFill]
}

nonisolated enum ScreenshotTradePlatformRegistry {
    private static let adapters: [any ScreenshotTradePlatformAdapter] = [
        TradovateScreenshotAdapter(),
        AlphaScreenshotAdapter(),
    ]

    static func detectPlatform(in rows: [ScreenshotTableRow]) -> ScreenshotImportPlatform {
        if adapters.contains(where: { $0.detect(in: rows) }) {
            return adapters.first(where: { $0.detect(in: rows) })?.platform ?? .generic
        }
        return .generic
    }

    static func adapter(for platform: ScreenshotImportPlatform) -> (any ScreenshotTradePlatformAdapter)? {
        adapters.first { $0.platform == platform }
    }

    static func parseFills(from rows: [ScreenshotTableRow]) -> [ParsedTradeFill] {
        if let adapter = adapters.first(where: { $0.detect(in: rows) }) {
            return adapter.parseFills(from: rows)
        }
        return ScreenshotGenericFillParser.parse(rows: rows)
    }
}

/// Tradovate screenshot semantics aligned with CSV `parseTradovate`.
nonisolated struct TradovateScreenshotAdapter: ScreenshotTradePlatformAdapter {
    var platform: ScreenshotImportPlatform { .tradovate }

    func detect(in rows: [ScreenshotTableRow]) -> Bool {
        guard let header = rows.first?.cells.map({ $0.lowercased() }) else { return false }
        let blob = header.joined(separator: " ")
        return blob.contains("buy") && blob.contains("sell") && (blob.contains("pnl") || blob.contains("p&l"))
    }

    func parseFills(from rows: [ScreenshotTableRow]) -> [ParsedTradeFill] {
        ScreenshotGenericFillParser.parse(rows: rows, platform: .tradovate)
    }
}

/// Alpha adapter shell — no invented column layouts until real fixtures exist.
nonisolated struct AlphaScreenshotAdapter: ScreenshotTradePlatformAdapter {
    var platform: ScreenshotImportPlatform { .alpha }

    func detect(in rows: [ScreenshotTableRow]) -> Bool {
        let blob = rows.prefix(3).flatMap(\.cells).joined(separator: " ").lowercased()
        return blob.contains("alphaticks") || blob.contains("alpha futures") || blob.contains("alpha ticks")
    }

    func parseFills(from rows: [ScreenshotTableRow]) -> [ParsedTradeFill] {
        // Fall back to generic until verified Alpha layouts exist in repo fixtures.
        ScreenshotGenericFillParser.parse(rows: rows, platform: .alpha)
    }
}
