import SwiftUI

/// Resolves linked trade / clip attachments already seeded in ``DetailPresentationCache``.
enum FeedLinkedContentResolver {
    static func linkedTrade(
        for entry: FeedTimelineEntry,
        cache: DetailPresentationCache
    ) -> Trade? {
        switch entry {
        case .post(_, let post):
            guard let tradeID = post.linkedTradeID else { return nil }
            return cache.trade(id: tradeID)
        case .clip(_, let reel):
            guard let tradeID = reel.linkedTradeID else { return nil }
            return cache.trade(id: tradeID)
        case .trade, .achievement:
            return nil
        }
    }

    static func linkedReel(
        for entry: FeedTimelineEntry,
        cache: DetailPresentationCache
    ) -> Reel? {
        switch entry {
        case .trade(_, let trade):
            return cache.reel(linkedTo: trade.id)
        case .post, .clip, .achievement:
            return nil
        }
    }
}

/// Compact linked-trade preview — tap opens trade detail only.
struct FeedLinkedTradeEmbed: View {
    let trade: Trade
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: ExperienceSpacing.md) {
                TradePreviewThumbnail(
                    trade: trade,
                    imagePipeline: imagePipeline,
                    size: .compact
                )

                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    PublicTradeHeadlineRow(
                        ticker: trade.symbol.ticker,
                        realizedPnL: trade.realizedPnL
                    )
                    PublicTradeMetaChipRow(trade: trade)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ExperienceIcon(icon: .forward, size: .sm, color: colors.tertiaryText)
            }
            .padding(ExperienceSpacing.sm)
            .background(
                colors.surfaceSecondary,
                in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Linked trade \(trade.symbol.ticker)")
        .accessibilityIdentifier("feed.linked.trade.\(trade.id.rawValue)")
    }
}

/// Linked clip preview for trade cards — thumbnail + play; tap opens clip detail only.
struct FeedLinkedClipEmbed: View {
    let reel: Reel
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: ExperienceSpacing.md) {
                ZStack(alignment: .center) {
                    TradeImageView(
                        reference: reel.thumbnail ?? reel.video,
                        imagePipeline: imagePipeline,
                        purpose: .reelThumbnail,
                        contentMode: .fill,
                        side: 60
                    )
                    ExperienceIcon(icon: .play, size: .md, color: .white)
                        .shadow(radius: 2)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(reel.caption?.isEmpty == false ? reel.caption! : "Linked clip")
                        .experienceStyle(.headline, color: colors.primaryText)
                        .lineLimit(2)
                    if let seconds = reel.durationSeconds, seconds > 0 {
                        Text(formatDuration(seconds))
                            .experienceStyle(.caption, color: colors.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ExperienceIcon(icon: .forward, size: .sm, color: colors.tertiaryText)
            }
            .padding(ExperienceSpacing.sm)
            .background(
                colors.surfaceSecondary,
                in: RoundedRectangle(cornerRadius: ExperienceRadius.md, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Linked clip")
        .accessibilityIdentifier("feed.linked.clip.\(reel.id.rawValue)")
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let seconds = max(0, totalSeconds)
        let mins = seconds / 60
        let secs = seconds % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }
}
