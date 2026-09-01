import Foundation
import OSLog

/// Non-sensitive trade mapping telemetry (DEBUG-only aggregate per load).
nonisolated enum TradeMappingTelemetry {
    #if DEBUG
    private static let logger = Logger(subsystem: AppLog.subsystem, category: "TradeMapping")
    nonisolated(unsafe) private static var loadLabel = ""
    nonisolated(unsafe) private static var decodedCount = 0
    nonisolated(unsafe) private static var nullableTickerCount = 0
    nonisolated(unsafe) private static var skippedCount = 0
    #endif

    static func beginLoad(_ label: String) {
        #if DEBUG
        loadLabel = label
        decodedCount = 0
        nullableTickerCount = 0
        skippedCount = 0
        #else
        _ = label
        #endif
    }

    static func recordDecoded() {
        #if DEBUG
        decodedCount &+= 1
        #endif
    }

    static func recordMissingTicker() {
        #if DEBUG
        nullableTickerCount &+= 1
        #endif
    }

    static func recordSkippedTrade() {
        #if DEBUG
        skippedCount &+= 1
        #endif
    }

    static func endLoad() {
        #if DEBUG
        guard !loadLabel.isEmpty else { return }
        logger.debug(
            "tradeMapping summary label=\(loadLabel, privacy: .public) decoded=\(decodedCount, privacy: .public) nullableTicker=\(nullableTickerCount, privacy: .public) skipped=\(skippedCount, privacy: .public)"
        )
        loadLabel = ""
        #endif
    }

    #if DEBUG
    static func missingTickerCountForTests() -> Int {
        nullableTickerCount
    }

    static func skippedCountForTests() -> Int {
        skippedCount
    }

    static func resetForTests() {
        loadLabel = ""
        decodedCount = 0
        nullableTickerCount = 0
        skippedCount = 0
    }
    #endif
}
