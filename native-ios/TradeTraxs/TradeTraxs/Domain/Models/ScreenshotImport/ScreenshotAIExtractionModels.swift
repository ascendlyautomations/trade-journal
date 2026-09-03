import Foundation

/// Phase 3 — versioned BFF contract for AI screenshot extraction.
nonisolated struct ScreenshotAIExtractRequest: Hashable, Codable, Sendable {
    var schemaVersion: String
    var requestFingerprint: String?
    var detectedPlatformHint: String?
    var deterministicWarnings: [String]
    var screenshots: [ScreenshotPayload]

    nonisolated struct ScreenshotPayload: Hashable, Codable, Sendable {
        var index: Int
        var mimeType: String
        var base64: String
        var ocrBlocks: [OCRBlockPayload]?
    }

    nonisolated struct OCRBlockPayload: Hashable, Codable, Sendable {
        var text: String
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }
}

nonisolated struct ScreenshotAIExtractResponse: Hashable, Codable, Sendable {
    var extraction: ScreenshotAIExtractionV1?
    var error: String?
}

nonisolated struct ScreenshotAIExtractionV1: Hashable, Codable, Sendable {
    var schemaVersion: String
    var detectedPlatform: String?
    var contentType: String
    var fills: [ScreenshotAIExtractFill]
    var completedTrades: [ScreenshotAIExtractCompletedTrade]
    var warnings: [String]
    var screenshotResults: [ScreenshotAIExtractScreenshotResult]
}

nonisolated struct ScreenshotAIField<T: Hashable & Codable & Sendable>: Hashable, Codable, Sendable {
    enum Provenance: String, Hashable, Codable, Sendable {
        case observed
        case inferred
        case missing
    }

    var value: T?
    var provenance: Provenance
}

nonisolated struct ScreenshotAIExtractFill: Hashable, Codable, Sendable, Identifiable {
    var id: String { "ai-fill-\(sourceImageIndex)-\(symbol.value ?? "x")-\(price.value.map { "\($0)" } ?? "p")" }
    var symbol: ScreenshotAIField<String>
    var side: ScreenshotAIField<String>
    var quantity: ScreenshotAIField<Double>
    var price: ScreenshotAIField<Double>
    var executedAt: ScreenshotAIField<String>
    var executionID: ScreenshotAIField<String>?
    var orderID: ScreenshotAIField<String>?
    var reportedPnL: ScreenshotAIField<Double>?
    var fees: ScreenshotAIField<Double>?
    var sourceImageIndex: Int
    var warnings: [String]?
}

nonisolated struct ScreenshotAIExtractCompletedTrade: Hashable, Codable, Sendable, Identifiable {
    var id: String { "ai-trade-\(sourceImageIndex)-\(symbol.value ?? "x")" }
    var symbol: ScreenshotAIField<String>
    var side: ScreenshotAIField<String>
    var quantity: ScreenshotAIField<Double>
    var entryPrice: ScreenshotAIField<Double>
    var exitPrice: ScreenshotAIField<Double>
    var entryAt: ScreenshotAIField<String>
    var exitAt: ScreenshotAIField<String>?
    var reportedPnL: ScreenshotAIField<Double>?
    var points: ScreenshotAIField<Double>?
    var executionID: ScreenshotAIField<String>?
    var orderID: ScreenshotAIField<String>?
    var sourceImageIndex: Int
    var warnings: [String]?
}

nonisolated struct ScreenshotAIExtractScreenshotResult: Hashable, Codable, Sendable {
    var index: Int
    var tradeLike: Bool
    var warnings: [String]
}

nonisolated enum ScreenshotExtractionQuality: String, Hashable, Codable, Sendable {
    case confident
    case uncertain
    case insufficient
}

#if DEBUG
nonisolated struct ScreenshotDeterministicDiagnostic: Hashable, Codable, Sendable {
    var platformDetected: String
    var fillsParsed: Int
    var completedRowsParsed: Int
    var failureCount: Int
    var averageOCRConfidence: Float
    var fallbackReason: String
}
#endif
