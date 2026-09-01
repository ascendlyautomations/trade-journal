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
        .contextMenu {
            Button {
                onOpen()
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            Button {
                onOpenAuthor()
            } label: {
                Label("View Profile", systemImage: "person.crop.circle")
            }
            Button {
                Task { await engagementStore.toggleLike(on: entry.interactionTarget) }
            } label: {
                Label("Like", systemImage: "heart")
            }
            Button {
                onOpen()
            } label: {
                Label("Comment", systemImage: "bubble.right")
            }
        } preview: {
            FeedItemRowPreview(entry: entry, author: author)
                .frame(width: 320)
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
                            target: entry.interactionTarget,
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
                target: entry.interactionTarget,
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
        EngagementBar(
            target: entry.interactionTarget,
            store: engagementStore,
            onCommentTap: onOpen
        )
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
            PublicTradeHeadlineRow(
                ticker: trade.symbol.ticker,
                realizedPnL: trade.realizedPnL
            )
            .accessibilityIdentifier("feed.trade.headline")

            PublicTradeMetaChipRow(trade: trade)
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

/// Lightweight feed context-menu preview — cached entry data only.
private struct FeedItemRowPreview: View {
    let entry: FeedTimelineEntry
    let author: Profile?

    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if let author {
                Text(author.displayName)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                Text("@\(author.username)")
                    .experienceStyle(.caption, color: colors.secondaryText)
            }
            Text(summaryTitle)
                .experienceStyle(.body, color: colors.primaryText)
                .lineLimit(4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfacePrimary)
    }

    private var summaryTitle: String {
        switch entry {
        case .trade(_, let trade):
            return "\(trade.symbol.ticker) · \(TradeDisplay.pnlText(trade.realizedPnL))"
        case .post(_, let post):
            return post.body
        case .clip(_, let reel):
            return reel.caption ?? "Clip"
        case .achievement(_, let achievement):
            return achievement.title
        }
    }
}
