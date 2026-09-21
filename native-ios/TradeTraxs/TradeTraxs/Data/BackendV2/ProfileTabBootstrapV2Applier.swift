import Foundation

nonisolated enum ProfileTabBootstrapV2Applier {
    @MainActor
    static func applyTradesTab(
        _ bootstrap: ProfileTabBootstrapV2,
        ownerID: ProfileID,
        detailCache: DetailPresentationCache?
    ) -> ProfileTabBootstrapApplier.Applied {
        var summaries: [TradeSummary] = []
        var skipped = 0
        for row in bootstrap.data.items {
            do {
                try row.validateSchema()
                summaries.append(try TradeSummaryMapper.map(from: row))
            } catch {
                skipped += 1
                TradeMappingTelemetry.recordSkippedTrade()
            }
        }

        detailCache?.seed(publicTradeSummaries: summaries, for: ownerID)

        #if DEBUG
        TradeSummaryProfileTelemetry.recordDecode(
            path: "v2.rpc",
            tradeCount: summaries.count,
            skipped: skipped
        )
        #endif

        return ProfileTabBootstrapApplier.Applied(
            tradeSummaries: summaries,
            reelLinkedTrades: nil,
            nextCursor: bootstrap.data.next_cursor,
            tradeEngagement: bootstrap.data.engagement,
            accountNames: nil,
            accountModes: nil,
            accountSizes: nil
        )
    }
}
