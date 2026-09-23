import Foundation

/// Profile / clip card title — linked trade public description takes precedence over reel caption.
enum ClipDisplayTitle {
    static func text(for reel: Reel, linkedTrade: Trade?) -> String {
        if reel.linkedTradeID != nil,
           let linkedTrade,
           let description = ClipLinkedTradeSection.descriptionText(for: linkedTrade)
        {
            return description
        }

        let caption = reel.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !caption.isEmpty {
            return caption
        }
        return "Clip"
    }

    static func text(for reel: Reel, cache: DetailPresentationCache) -> String {
        let linkedTrade: Trade? = {
            guard let tradeID = reel.linkedTradeID else { return nil }
            guard let summary = cache.tradeSummary(id: tradeID) else { return nil }
            return TradeSummaryMapper.previewTrade(from: summary)
        }()
        return text(for: reel, linkedTrade: linkedTrade)
    }
}
