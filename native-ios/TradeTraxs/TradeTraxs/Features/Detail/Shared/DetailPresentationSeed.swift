import Foundation

/// Non-authoritative detail shell — list/card snapshot only. Never used for edit or completeness checks.
nonisolated struct DetailPresentationSeed: Sendable, Equatable {
    var summary: TradeSummary

    /// Legacy `Trade` projection for existing detail UI shell (missing detail-only fields by design).
    var previewTrade: Trade {
        TradeSummaryMapper.previewTrade(from: summary)
    }
}
