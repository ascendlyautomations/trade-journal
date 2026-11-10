import SwiftUI

/// Resolves linked trade / clip attachments already seeded in ``DetailPresentationCache``.
enum FeedLinkedContentResolver {
    static func linkedTradeSummary(
        for entry: FeedTimelineEntry,
        cache: DetailPresentationCache
    ) -> TradeSummary? {
        switch entry {
        case .post(_, let post):
            guard let tradeID = post.linkedTradeID else { return nil }
            return cache.tradeSummary(id: tradeID)
        case .clip(_, let reel):
            guard let tradeID = reel.linkedTradeID else { return nil }
            return cache.tradeSummary(id: tradeID)
        case .trade, .achievement:
            return nil
        }
    }

    /// Card/overlay preview — prefer ``linkedTradeSummary(for:cache:)`` (no legacy full-trade accessor).
    static func linkedTrade(
        for entry: FeedTimelineEntry,
        cache: DetailPresentationCache
    ) -> Trade? {
        guard let summary = linkedTradeSummary(for: entry, cache: cache) else { return nil }
        return TradeSummaryMapper.previewTrade(from: summary)
    }

    static func linkedReel(
        for entry: FeedTimelineEntry,
        cache: DetailPresentationCache
    ) -> Reel? {
        switch entry {
        case .trade(_, let summary):
            return visibleLinkedReel(for: summary.id, cache: cache, viewerID: nil)
        case .post, .clip, .achievement:
            return nil
        }
    }

    /// Trade detail / profile — respect reel visibility for the signed-in viewer when known.
    static func visibleLinkedReel(
        for tradeID: TradeID,
        cache: DetailPresentationCache,
        viewerID: ProfileID?
    ) -> Reel? {
        guard let reel = cache.reel(linkedTo: tradeID) else { return nil }
        guard isReelVisibleToViewer(reel, viewerID: viewerID, cache: cache) else { return nil }
        return reel
    }

    private static func isReelVisibleToViewer(
        _ reel: Reel,
        viewerID: ProfileID?,
        cache: DetailPresentationCache
    ) -> Bool {
        if let viewerID, viewerID == reel.authorProfileID { return true }
        switch reel.visibility {
        case .public:
            return true
        case .private:
            return false
        case .followersOnly:
            guard viewerID != nil else { return true }
            return cache.viewerFollowEdge(for: reel.authorProfileID) == true
        }
    }
}

/// Compact linked-trade preview — tap opens trade detail only.
struct FeedLinkedTradeEmbed: View {
    let summary: TradeSummary
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    init(trade: Trade, imagePipeline: any ImagePipeline, onOpen: @escaping () -> Void) {
        self.init(
            summary: TradeSummaryMapper.summary(fromPartialListTrade: trade),
            imagePipeline: imagePipeline,
            onOpen: onOpen
        )
    }

    init(summary: TradeSummary, imagePipeline: any ImagePipeline, onOpen: @escaping () -> Void) {
        self.summary = summary
        self.imagePipeline = imagePipeline
        self.onOpen = onOpen
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: ExperienceSpacing.md) {
                TradeImageView(
                    reference: ProfileCardMediaPresence.tradeMedia(in: summary),
                    imagePipeline: imagePipeline,
                    purpose: .tradeScreenshot,
                    contentMode: .fill,
                    side: 60
                )

                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    PublicTradeHeadlineRow(
                        ticker: summary.symbol.ticker,
                        realizedPnL: summary.realizedPnL
                    )
                    PublicTradeMetaChipRow(summary: summary)
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
        .buttonStyle(.experiencePlain)
        .accessibilityLabel("Linked trade \(summary.symbol.ticker)")
        .accessibilityIdentifier("feed.linked.trade.\(summary.id.rawValue)")
    }
}

/// Portrait thumbnail + play overlay — shared by feed embeds and trade metrics accessory.
struct FeedLinkedClipThumbnail: View {
    let reel: Reel
    let imagePipeline: any ImagePipeline
    var side: CGFloat = 56

    var body: some View {
        ZStack(alignment: .center) {
            TradeImageView(
                reference: reel.thumbnail ?? reel.video,
                imagePipeline: imagePipeline,
                purpose: .reelThumbnail,
                contentMode: .fill,
                side: side
            )
            ExperienceIcon(icon: .play, size: .md, color: .white)
                .shadow(radius: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: ExperienceRadius.sm, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Small horizontal linked-clip row — thumbnail, label, duration (trade detail / profile cards).
struct FeedLinkedClipCompactPreview: View {
    let reel: Reel
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void
    var thumbnailSide: CGFloat = 36

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: ExperienceSpacing.xs) {
                FeedLinkedClipThumbnail(reel: reel, imagePipeline: imagePipeline, side: thumbnailSide)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Linked Clip")
                        .experienceStyle(.caption2, color: colors.secondaryText)
                        .lineLimit(1)
                    if let seconds = reel.durationSeconds, seconds > 0 {
                        Text("\(seconds) sec")
                            .experienceStyle(.caption2, color: colors.tertiaryText)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel("Linked Clip")
        .accessibilityIdentifier("feed.linkedClip.compact.\(reel.id.rawValue)")
    }
}

/// Trade detail header — horizontal clip row sized to align with entry/date/account lines.
struct FeedLinkedClipTradeDetailHeaderRow: View {
    let reel: Reel
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    private let thumbnailSide: CGFloat = 46

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: ExperienceSpacing.xs) {
                FeedLinkedClipThumbnail(reel: reel, imagePipeline: imagePipeline, side: thumbnailSide)

                HStack(spacing: ExperienceSpacing.xxs) {
                    Text("Linked Clip")
                        .font(.system(.caption, design: .default).weight(.medium))
                        .foregroundStyle(colors.secondaryText)
                        .lineLimit(1)
                    if let seconds = reel.durationSeconds, seconds > 0 {
                        Text("\(seconds) sec")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(colors.tertiaryText)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel("Linked Clip")
        .accessibilityIdentifier("detail.trade.linkedClip.\(reel.id.rawValue)")
    }
}

/// Compact linked clip beside trade Entry/Exit metrics — thumbnail, label, duration (seconds).
struct FeedLinkedClipMetricsAccessory: View {
    let reel: Reel
    let imagePipeline: any ImagePipeline
    let onOpen: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .center, spacing: ExperienceSpacing.xxs) {
                FeedLinkedClipThumbnail(reel: reel, imagePipeline: imagePipeline, side: 52)

                Text("Linked Clip")
                    .experienceStyle(.caption2, color: colors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let seconds = reel.durationSeconds, seconds > 0 {
                    Text("\(seconds) sec")
                        .experienceStyle(.caption2, color: colors.tertiaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .frame(width: 60, alignment: .center)
        }
        .buttonStyle(.experiencePlain)
        .accessibilityLabel("Linked Clip")
        .accessibilityIdentifier("detail.trade.linkedClip.\(reel.id.rawValue)")
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
                FeedLinkedClipThumbnail(reel: reel, imagePipeline: imagePipeline, side: 60)

                VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
                    Text(ReelCaptionDisplay.displayText(for: reel))
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
        .buttonStyle(.experiencePlain)
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
