import Foundation

/// One execution/fill extracted from a screenshot before aggregation.
nonisolated struct ParsedTradeFill: Hashable, Codable, Sendable, Identifiable {
    enum Action: String, Hashable, Codable, Sendable {
        case buy
        case sell
    }

    var id: String
    var symbol: String
    var action: Action
    var quantity: Decimal
    var price: Decimal
    var executedAt: Date
    var reportedPnL: Decimal?
    var commission: Decimal?
    var executionID: String?
    var orderID: String?
    var sourcePlatform: ScreenshotImportPlatform?
    var sourceImageIndex: Int
    var sourceRowIndex: Int
    var warnings: [String]

    var signedQuantityDelta: Decimal {
        action == .buy ? quantity : -quantity
    }

    var sideLabel: String {
        action == .buy ? "BUY" : "SELL"
    }
}

nonisolated enum ScreenshotImportPlatform: String, Hashable, Codable, Sendable, CaseIterable {
    case generic
    case tradovate
    case alpha

    var displayName: String {
        switch self {
        case .generic: return "Generic"
        case .tradovate: return "Tradovate"
        case .alpha: return "Alpha"
        }
    }
}

/// Metadata for screenshot import review — not persisted on `CSVParsedTrade`.
nonisolated struct ScreenshotImportTradeMetadata: Hashable, Codable, Sendable {
    enum AggregationSource: String, Hashable, Codable, Sendable {
        case completedRow
        case fillAggregation
    }

    enum PnLSource: String, Hashable, Codable, Sendable {
        case reported
        case calculated
        case reportedAndCalculated
    }

    var fills: [ParsedTradeFill]
    var entryFillCount: Int
    var exitFillCount: Int
    var aggregationSource: AggregationSource
    var reportedPnL: Decimal?
    var calculatedPnL: Decimal?
    var pnlSource: PnLSource
    var aggregatedFees: Decimal?
    var importFingerprint: String?
    var duplicateClassification: ImportDuplicateClassification
    var isSelectedForImport: Bool
    var warnings: [String]
    var extractionSource: ExtractionSource

    enum ExtractionSource: String, Hashable, Codable, Sendable {
        case deterministic
        case aiAssisted
    }

    static func empty(classification: ImportDuplicateClassification = .newTrade) -> ScreenshotImportTradeMetadata {
        ScreenshotImportTradeMetadata(
            fills: [],
            entryFillCount: 0,
            exitFillCount: 0,
            aggregationSource: .completedRow,
            reportedPnL: nil,
            calculatedPnL: nil,
            pnlSource: .reported,
            aggregatedFees: nil,
            importFingerprint: nil,
            duplicateClassification: classification,
            isSelectedForImport: classification != .exactDuplicate,
            warnings: [],
            extractionSource: .deterministic
        )
    }
}

nonisolated enum ImportDuplicateClassification: String, Hashable, Codable, Sendable {
    case newTrade
    case possibleDuplicate
    case exactDuplicate

    var reviewLabel: String? {
        switch self {
        case .newTrade: return nil
        case .possibleDuplicate: return "Possible duplicate"
        case .exactDuplicate: return "Exact duplicate"
        }
    }
}

nonisolated enum TradeImportSource: String, Hashable, Codable, Sendable {
    case manual
    case csv
    case screenshot
}
