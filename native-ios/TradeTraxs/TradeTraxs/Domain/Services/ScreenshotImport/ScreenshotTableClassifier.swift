import Foundation

/// Content classification before semantic parsing.
nonisolated enum ScreenshotTableKind: String, Hashable, Codable, Sendable {
    case completedTrades
    case executions
    case unknown
}

nonisolated enum ScreenshotTableClassifier {
    static func classify(table: ScreenshotStructuredTable) -> ScreenshotTableKind {
        let headerKeys = Set(table.columns.map(\.key))
        let completedScore = scoreCompleted(headers: headerKeys, rows: table.dataRows)
        let executionScore = scoreExecutions(headers: headerKeys, rows: table.dataRows)

        if completedScore >= 4 && completedScore > executionScore + 1 {
            return .completedTrades
        }
        if executionScore >= 3 && executionScore > completedScore {
            return .executions
        }
        if completedScore >= 3 && executionScore <= 1 {
            return .completedTrades
        }
        if executionScore >= 2 && completedScore <= 1 {
            return .executions
        }
        return .unknown
    }

    private static func scoreCompleted(
        headers: Set<ScreenshotColumnKey>,
        rows: [ScreenshotStructuredRow]
    ) -> Int {
        var score = 0
        if headers.contains(.openPrice) && headers.contains(.closePrice) { score += 3 }
        if headers.contains(.openTime) && headers.contains(.closeTime) { score += 2 }
        if headers.contains(.pnl) { score += 2 }
        if headers.contains(.side) || headers.contains(.position) || headers.contains(.openSide) { score += 1 }
        if headers.contains(.tradeID) { score += 1 }
        if headers.contains(.volume) { score += 1 }

        let blob = rows.flatMap(\.allCellTexts).joined(separator: " ").lowercased()
        if blob.contains("open price") || blob.contains("close price") { score += 1 }
        if blob.contains("long") || blob.contains("short") { score += 1 }
        return score
    }

    private static func scoreExecutions(
        headers: Set<ScreenshotColumnKey>,
        rows: [ScreenshotStructuredRow]
    ) -> Int {
        var score = 0
        if headers.contains(.status) { score += 3 }
        if headers.contains(.orderType) { score += 2 }
        if headers.contains(.action) { score += 1 }

        var filledCount = 0
        var cancelledCount = 0
        var marketLimitCount = 0
        var openClosePriceCount = 0

        for row in rows {
            let joined = row.allCellTexts.joined(separator: " ").uppercased()
            if containsStatus(joined, status: "FILLED") { filledCount += 1 }
            if containsStatus(joined, status: "CANCELLED") || joined.contains("CANCELED") { cancelledCount += 1 }
            if joined.contains("MARKET") || joined.contains("LIMIT") { marketLimitCount += 1 }
            if row.value(for: .openPrice) != nil && row.value(for: .closePrice) != nil { openClosePriceCount += 1 }
        }

        if filledCount > 0 { score += 2 }
        if cancelledCount > 0 { score += 2 }
        if marketLimitCount > 0 { score += 2 }
        if openClosePriceCount == 0 && (filledCount + cancelledCount) >= 2 { score += 2 }

        // Execution tables should not have both open and close prices per row.
        if openClosePriceCount > 0 { score -= 2 }
        return max(0, score)
    }

    private static func containsStatus(_ haystack: String, status: String) -> Bool {
        if haystack.contains(status) { return true }
        if status == "FILLED", haystack.contains("ALLED") { return true }
        return false
    }
}
