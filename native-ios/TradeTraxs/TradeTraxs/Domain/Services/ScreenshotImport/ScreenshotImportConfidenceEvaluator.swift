import Foundation

/// Determines whether deterministic extraction is sufficient or AI fallback should be offered.
nonisolated enum ScreenshotImportConfidenceEvaluator {
    static func evaluate(
        result: ScreenshotImportProcessResult,
        blocksByImage: [[OCRTextBlock]]
    ) -> ScreenshotExtractionQuality {
        let summary = result.summary
        if summary.successCount == 0 {
            return .insufficient
        }

        let reviewRatio = Double(summary.needsReviewCount) / Double(max(summary.successCount, 1))
        let failureRatio = Double(summary.failedCount) / Double(max(summary.totalRows, 1))
        let avgConfidence = averageOCRConfidence(blocksByImage)

        if summary.successCount > 0, reviewRatio >= 0.95, failureRatio >= 0.5 {
            return .uncertain
        }
        if avgConfidence < 0.52, reviewRatio >= 0.6 {
            return .uncertain
        }
        if result.fillsProcessed == 0, summary.successCount > 0, reviewRatio >= 0.8 {
            return .uncertain
        }
        return .confident
    }

    static func fallbackReason(
        result: ScreenshotImportProcessResult,
        blocksByImage: [[OCRTextBlock]]
    ) -> String {
        if result.summary.successCount == 0 {
            if blocksByImage.flatMap({ $0 }).isEmpty {
                return "We couldn't read text from this screenshot."
            }
            return "We couldn't confidently read this trade history."
        }
        return "Some rows need review — AI may help with unclear layouts."
    }

    #if DEBUG
    static func diagnostic(
        result: ScreenshotImportProcessResult,
        blocksByImage: [[OCRTextBlock]],
        platform: ScreenshotImportPlatform
    ) -> ScreenshotDeterministicDiagnostic {
        ScreenshotDeterministicDiagnostic(
            platformDetected: platform.rawValue,
            fillsParsed: result.fillsProcessed,
            completedRowsParsed: result.summary.successCount,
            failureCount: result.summary.failedCount,
            averageOCRConfidence: averageOCRConfidence(blocksByImage),
            fallbackReason: fallbackReason(result: result, blocksByImage: blocksByImage)
        )
    }
    #endif

    private static func averageOCRConfidence(_ blocksByImage: [[OCRTextBlock]]) -> Float {
        let values = blocksByImage.flatMap { $0.map(\.confidence) }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Float(values.count)
    }
}
