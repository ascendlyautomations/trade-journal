import SwiftUI

/// Instagram-style continuous feed row — media-first when media exists, text-first otherwise.
struct FeedItemRow: View {
    let entry: FeedTimelineEntry
    let author: Profile?
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    let onOpen: () -> Void
    let onOpenAuthor: () -> Void

    @Environment(\.themeColors) private var colors
    @Environment(\.experienceTheme) private var theme

    private let badgeColumns = [
        GridItem(.adaptive(minimum: 52), spacing: ExperienceSpacing.xs, alignment: .leading),
    ]

    private var interactionTarget: InteractionTarget {
        switch entry {
        case .trade(_, let trade): return .trade(trade.id)
        case .post(_, let post): return .profilePost(post.id)
        case .clip(_, let reel): return .reel(reel.id)
        case .achievement(_, let achievement): return .achievement(achievement.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeedAuthorHeader(
                profile: author,
                fallbackID: entry.authorProfileID,
                timestamp: entry.createdAt,
                imagePipeline: imagePipeline,
                onOpenAuthor: onOpenAuthor
            )
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, ExperienceSpacing.sm)

            if entry.hasDisplayMedia {
                mediaLayout
            } else {
                textLayout
            }

            Rectangle()
                .fill(colors.border.opacity(0.55))
                .frame(height: ExperienceBorder.hairline)
                .accessibilityHidden(true)
        }
        .accessibilityIdentifier("feed.row.\(entry.id)")
    }

    // MARK: - Layout A (media)

    private var mediaLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            mediaContent
                .allowsHitTesting(false)
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .experienceDoubleTapLike(
                            target: interactionTarget,
                            store: engagementStore,
                            onSingleTap: onOpen
                        )
                }

            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                engagement
                summary
                caption(lineLimit: 2)
            }
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.sm)
            .padding(.bottom, ExperienceSpacing.md)
        }
    }

    // MARK: - Layout B (text-only — engagement outside open target)

    private var textLayout: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                summary
                caption(lineLimit: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .experienceDoubleTapLike(
                target: interactionTarget,
                store: engagementStore,
                onSingleTap: onOpen
            )

            engagement
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.md)
    }

    // MARK: - Media (full bleed — only when hasDisplayMedia)

    @ViewBuilder
    private var mediaContent: some View {
        switch entry {
        case .trade(_, let trade):
            AspectFitMediaView(
                reference: trade.thumbnail,
                purpose: .tradeScreenshot,
                imagePipeline: imagePipeline,
                accessibilityIdentifier: "feed.trade.media",
                emptyIcon: .chart,
                allowsFullResolutionViewer: false,
                showsPlaceholderWhenUnavailable: false
            )

        case .post(_, let post):
            if let first = post.media.first(where: {
                !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                AspectFitMediaView(
                    reference: first,
                    purpose: .postImage,
                    imagePipeline: imagePipeline,
                    accessibilityIdentifier: "feed.post.media",
                    emptyIcon: .photo,
                    allowsFullResolutionViewer: false,
                    showsPlaceholderWhenUnavailable: false
                )
            }

        case .clip(_, let reel):
            ZStack(alignment: .bottomTrailing) {
                AspectFitMediaView(
                    reference: reel.thumbnail ?? reel.video,
                    purpose: .reelThumbnail,
                    imagePipeline: imagePipeline,
                    accessibilityIdentifier: "feed.clip.media",
                    emptyIcon: .video,
                    allowsFullResolutionViewer: false,
                    showsPlaceholderWhenUnavailable: false
                )

                ExperienceIcon(icon: .play, size: .lg, color: .white)
                    .padding(ExperienceSpacing.md)
                    .shadow(radius: 2)
            }

        case .achievement(_, let achievement):
            AspectFitMediaView(
                reference: achievement.image,
                purpose: .postImage,
                imagePipeline: imagePipeline,
                accessibilityIdentifier: "feed.achievement.media",
                emptyIcon: .leaderboard,
                allowsFullResolutionViewer: false,
                showsPlaceholderWhenUnavailable: false
            )
        }
    }

    // MARK: - Engagement

    @ViewBuilder
    private var engagement: some View {
        switch entry {
        case .trade(_, let trade):
            EngagementBar(target: .trade(trade.id), store: engagementStore, onCommentTap: onOpen)
        case .post(_, let post):
            EngagementBar(target: .profilePost(post.id), store: engagementStore, onCommentTap: onOpen)
        case .clip(_, let reel):
            EngagementBar(target: .reel(reel.id), store: engagementStore, onCommentTap: onOpen)
        case .achievement(_, let achievement):
            EngagementBar(target: .achievement(achievement.id), store: engagementStore, onCommentTap: onOpen)
        }
    }

    // MARK: - Summary (trade chips / titles)

    @ViewBuilder
    private var summary: some View {
        switch entry {
        case .trade(_, let trade):
            tradeSummary(trade)
        case .post:
            EmptyView()
        case .clip:
            EmptyView()
        case .achievement(_, let achievement):
            Text(achievement.title)
                .experienceStyle(.headline, color: colors.primaryText)
                .lineLimit(entry.hasDisplayMedia ? 2 : 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tradeSummary(_ trade: Trade) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(trade.symbol.ticker)
                    .experienceStyle(.title, color: colors.primaryText)
                Spacer(minLength: ExperienceSpacing.sm)
                Text(TradeDisplay.pnlText(trade.realizedPnL))
                    .experienceStyle(
                        .metricLarge,
                        color: theme.metricColor(
                            for: NSDecimalNumber(decimal: trade.realizedPnL?.amount ?? 0).doubleValue
                        )
                    )
            }
            .accessibilityIdentifier("feed.trade.headline")

            LazyVGrid(columns: badgeColumns, alignment: .leading, spacing: ExperienceSpacing.xs) {
                ExperienceTag(
                    title: TradeDisplay.sideTitle(trade.side),
                    tone: trade.side == .long ? .success : .error
                )
                if trade.riskReward != nil {
                    ExperienceTag(title: TradeDisplay.rrText(trade.riskReward), tone: .info)
                }
                ExperienceTag(title: TradeDisplay.quantityBadgeText(trade.quantity), tone: .info)
                if let session = trade.sessionLabel?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !session.isEmpty
                {
                    ExperienceTag(title: session, tone: .info)
                }
            }
            .accessibilityIdentifier("feed.trade.badges")
        }
    }

    // MARK: - Caption

    @ViewBuilder
    private func caption(lineLimit: Int) -> some View {
        if let text = previewText, !text.isEmpty {
            Text(text)
                .experienceStyle(.body, color: colors.primaryText)
                .lineLimit(lineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("feed.caption")
        }
    }

    private var previewText: String? {
        switch entry {
        case .trade(_, let trade):
            return trade.publicCaption?.trimmingCharacters(in: .whitespacesAndNewlines)
        case .post(_, let post):
            return post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        case .clip(_, let reel):
            return reel.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        case .achievement(_, let achievement):
            return achievement.description?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
