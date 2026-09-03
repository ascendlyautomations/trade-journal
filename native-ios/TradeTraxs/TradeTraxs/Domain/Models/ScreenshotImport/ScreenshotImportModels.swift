import CoreGraphics
import Foundation

/// Vision OCR text block with layout — used before trade semantics.
nonisolated struct OCRTextBlock: Hashable, Codable, Sendable, Identifiable {
    var id: String
    var text: String
    /// Normalized Vision bounding box (origin bottom-left, 0…1).
    var boundingBox: CGRect
    var confidence: Float

    var midX: CGFloat { boundingBox.midX }
    var midY: CGFloat { boundingBox.midY }
}

/// Reconstructed table row from OCR blocks.
nonisolated struct ScreenshotTableRow: Hashable, Codable, Sendable, Identifiable {
    var id: Int
    var cells: [String]
    var yCenter: CGFloat
    var sourceImageIndex: Int
}

/// Column definition from header geometry.
nonisolated struct ScreenshotTableColumn: Hashable, Codable, Sendable, Identifiable {
    var id: String { key.rawValue }
    var key: ScreenshotColumnKey
    var headerText: String
    var xMin: CGFloat
    var xMax: CGFloat
    var columnIndex: Int

    var xCenter: CGFloat { (xMin + xMax) / 2 }
}

/// Row with header-keyed cell values from X-coordinate assignment.
nonisolated struct ScreenshotStructuredRow: Hashable, Codable, Sendable, Identifiable {
    var id: Int
    var values: [ScreenshotColumnKey: String]
    var allCellTexts: [String]
    var yCenter: CGFloat
    var sourceImageIndex: Int

    func value(for key: ScreenshotColumnKey) -> String? {
        guard let raw = values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw
    }
}

/// Geometry-reconstructed table ready for classification and parsing.
nonisolated struct ScreenshotStructuredTable: Hashable, Codable, Sendable {
    var columns: [ScreenshotTableColumn]
    var headerRowIndex: Int?
    var dataRows: [ScreenshotStructuredRow]
    var legacyRows: [ScreenshotTableRow]
    var sourceImageIndex: Int

    var columnKeys: Set<ScreenshotColumnKey> {
        Set(columns.map(\.key))
    }
}

/// Safe DEBUG diagnostics — no account IDs, emails, balances, or raw OCR dumps.
nonisolated struct ScreenshotImportDiagnostics: Hashable, Codable, Sendable {
    var ocrObservationCount: Int
    var detectedHeaders: [String]
    var tableKind: ScreenshotTableKind
    var reconstructedRowCount: Int
    var completedTradeCandidates: Int
    var executionCandidates: Int
    var ignoredCancelledRows: Int
    var rejectedRows: [ScreenshotImportRejectedRow]
    var reviewWarnings: [String]
}

nonisolated struct ScreenshotImportRejectedRow: Hashable, Codable, Sendable {
    var rowIndex: Int
    var reason: String
}

/// Parsed trade or execution candidate — Phase 2 fill aggregation consumes `.executionFill`.
nonisolated struct ScreenshotParsedCandidate: Hashable, Codable, Sendable, Identifiable {
    enum Kind: String, Hashable, Codable, Sendable {
        case completedTrade
        case executionFill
    }

    var id: String
    var kind: Kind
    var symbol: String?
    var side: TradeSide?
    var quantity: Decimal?
    var entryPrice: Decimal?
    var exitPrice: Decimal?
    var entryAt: Date?
    var exitAt: Date?
    var realizedPnL: Decimal?
    var points: Decimal?
    var executionID: String?
    var orderID: String?
    var warnings: [String]
    var sourceImageIndex: Int
    var sourceRowIndex: Int
}

nonisolated struct ScreenshotImportParseResult: Hashable, Codable, Sendable {
    var candidates: [ScreenshotParsedCandidate]
    var failures: [CSVParseRowFailure]
    var imagesProcessed: Int
}

/// Phase 2 pipeline output — trades plus parallel screenshot review metadata.
nonisolated struct ScreenshotImportProcessResult: Hashable, Codable, Sendable {
    var summary: CSVParseSummary
    var metadataByTradeID: [String: ScreenshotImportTradeMetadata]
    var fillsProcessed: Int
    var fillsDeduped: Int
    var extractionQuality: ScreenshotExtractionQuality
    var isAIAssisted: Bool
    var aiWarnings: [String]

    init(
        summary: CSVParseSummary,
        metadataByTradeID: [String: ScreenshotImportTradeMetadata],
        fillsProcessed: Int,
        fillsDeduped: Int,
        extractionQuality: ScreenshotExtractionQuality = .confident,
        isAIAssisted: Bool = false,
        aiWarnings: [String] = []
    ) {
        self.summary = summary
        self.metadataByTradeID = metadataByTradeID
        self.fillsProcessed = fillsProcessed
        self.fillsDeduped = fillsDeduped
        self.extractionQuality = extractionQuality
        self.isAIAssisted = isAIAssisted
        self.aiWarnings = aiWarnings
    }
}
