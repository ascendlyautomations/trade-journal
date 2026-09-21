import SwiftUI

/// Instagram-style continuous feed row — media-first when media exists, text-first otherwise.
struct FeedItemRow: View {
    let entry: FeedTimelineEntry
    let author: Profile?
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    let vaultStore: VaultStore
    let detailCache: DetailPresentationCache
    let playbackCoordinator: FeedVideoPlaybackCoordinator
    let onOpen: () -> Void
    let onOpenAuthor: () -> Void
    let onOpenLinkedTrade: (TradeID) -> Void
    let onOpenLinkedClip: (ReelID) -> Void
    var viewerID: ProfileID?
    var onReport: (() -> Void)?
    var onShare: (() -> Void)?

    @Environment(\.themeColors) private var colors
    @State private var showsVaultSheet = false

    private var vaultRef: VaultContentRef? { VaultContentRef.from(entry.interactionTarget) }
    private var isVaulted: Bool {
        guard let vaultRef else { return false }
        return vaultStore.state(for: vaultRef).isVaulted
    }

    private var linkedTradeSummary: TradeSummary? {
        guard let trade = FeedLinkedContentResolver.linkedTrade(for: entry, cache: detailCache) else {
            return nil
        }
        return TradeSummaryMapper.summary(fromPartialListTrade: trade)
    }

    private var linkedReel: Reel? {
        FeedLinkedContentResolver.linkedReel(for: entry, cache: detailCache)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeedAuthorHeader(
                profile: author,
                fallbackID: entry.authorProfileID,
                timestamp: entry.createdAt,
                imagePipeline: imagePipeline,
                onOpenAuthor: onOpenAuthor,
                isOwner: viewerID == entry.authorProfileID,
                onReport: onReport,
                onAddToVault: vaultRef == nil ? nil : { openVaultSheet() },
                onManageInVault: vaultRef == nil || !isVaulted ? nil : { openVaultSheet() }
            )
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.vertical, isClipRow ? ExperienceSpacing.xs : ExperienceSpacing.sm)

            if entry.hasDisplayMedia {
                standardMediaLayout
            } else {
                textLayout
            }

            FeedSectionSeparator()
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
            if onShare != nil {
                Button {
                    onShare?()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        } preview: {
            FeedItemRowPreview(entry: entry, author: author)
                .frame(width: 320)
        }
        .accessibilityIdentifier("feed.row.\(entry.id)")
        .sheet(isPresented: $showsVaultSheet) {
            if let vaultRef {
                VaultDestinationSheet(ref: vaultRef, store: vaultStore)
            }
        }
    }

    private func openVaultSheet() {
        vaultStore.loadFoldersIfNeeded()
        showsVaultSheet = true
    }

    private var isClipRow: Bool {
        if case .clip = entry { return true }
        return false
    }

    /// Media-first rows — engagement attached directly under media, caption below.
    private var standardMediaLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            feedImageMedia
            mediaFooter
        }
    }

    private var mediaFooter: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            engagement
            summary
            feedCaptionPreview
            linkedEmbeds
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.top, ExperienceSpacing.xxs)
        .padding(.bottom, ExperienceSpacing.sm)
    }

    // MARK: - Layout B (text-only — engagement outside open target)

    private var textLayout: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                summary
                feedCaptionPreview
                linkedEmbeds
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
    private var feedImageMedia: some View {
        switch entry {
        case .trade(_, let summary):
            InteractiveImageView(
                mediaID: entry.id,
                reference: summary.thumbnail,
                purpose: .tradeScreenshot,
                imagePipeline: imagePipeline,
                emptyIcon: .chart,
                accessibilityIdentifier: "feed.trade.media",
                deliveryQuality: .feedDisplay,
                auditSurface: "feed",
                onSingleTap: onOpen,
                onDoubleTapLike: {
                    Task { await engagementStore.ensureLiked(on: entry.interactionTarget) }
                }
            )

        case .post(_, let post):
            if let first = post.media.first(where: {
                !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                InteractiveImageView(
                    mediaID: entry.id,
                    reference: first,
                    purpose: .postImage,
                    imagePipeline: imagePipeline,
                    emptyIcon: .photo,
                    accessibilityIdentifier: "feed.post.media",
                    deliveryQuality: .feedDisplay,
                    auditSurface: "feed",
                    onSingleTap: onOpen,
                    onDoubleTapLike: {
                        Task { await engagementStore.ensureLiked(on: entry.interactionTarget) }
                    }
                )
            }

        case .clip(_, let reel):
            FeedClipMediaView(
                feedItemID: entry.id,
                reel: reel,
                imagePipeline: imagePipeline,
                playbackCoordinator: playbackCoordinator,
                onTogglePlayPause: {
                    playbackCoordinator.togglePlayPause(for: reel)
                },
                onDoubleTapLike: {
                    Task { await engagementStore.ensureLiked(on: entry.interactionTarget) }
                }
            )
            .fixedSize(horizontal: false, vertical: true)

        case .achievement(_, let achievement):
            InteractiveImageView(
                mediaID: entry.id,
                reference: achievement.image,
                purpose: .postImage,
                imagePipeline: imagePipeline,
                emptyIcon: .leaderboard,
                accessibilityIdentifier: "feed.achievement.media",
                deliveryQuality: .feedDisplay,
                auditSurface: "feed",
                onSingleTap: onOpen,
                onDoubleTapLike: {
                    Task { await engagementStore.ensureLiked(on: entry.interactionTarget) }
                }
            )
        }
    }

    // MARK: - Linked attachments

    @ViewBuilder
    private var linkedEmbeds: some View {
        if let linkedTradeSummary {
            FeedLinkedTradeEmbed(
                summary: linkedTradeSummary,
                imagePipeline: imagePipeline,
                onOpen: { onOpenLinkedTrade(linkedTradeSummary.id) }
            )
        }
        if let linkedReel {
            FeedLinkedClipEmbed(
                reel: linkedReel,
                imagePipeline: imagePipeline,
                onOpen: { onOpenLinkedClip(linkedReel.id) }
            )
        }
    }

    private var isImagePostRow: Bool {
        guard case .post(_, let post) = entry else { return false }
        return post.media.contains {
            !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var postCaptionText: String? {
        guard case .post(_, let post) = entry else { return nil }
        let trimmed = post.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Engagement

    @ViewBuilder
    private var engagement: some View {
        EngagementBar(
            target: entry.interactionTarget,
            store: engagementStore,
            vaultStore: vaultStore,
            onCommentTap: onOpen,
            onShareTap: onShare,
            vaultRef: vaultRef,
            visualStyle: .feedCard
        )
    }

    // MARK: - Summary (trade chips / titles)

    @ViewBuilder
    private var summary: some View {
        switch entry {
        case .trade(_, let summary):
            tradeSummary(summary)
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

    private func tradeSummary(_ summary: TradeSummary) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            PublicTradeHeadlineRow(
                ticker: summary.symbol.ticker,
                realizedPnL: summary.realizedPnL
            )
            .accessibilityIdentifier("feed.trade.headline")

            PublicTradeMetaChipRow(summary: summary)
                .accessibilityIdentifier("feed.trade.badges")
        }
    }

    // MARK: - Caption

    @ViewBuilder
    private var feedCaptionPreview: some View {
        if let text = entry.feedCaptionText,
           let lineLimit = entry.feedCaptionLineLimit
        {
            FeedCaptionPreview(
                text: text,
                lineLimit: lineLimit,
                onSeeMore: onOpen,
                seeMoreAccessibilityIdentifier: isImagePostRow
                    ? "feed.post.seeMore"
                    : "feed.caption.seeMore"
            )
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
        case .trade(_, let summary):
            return "\(summary.symbol.ticker) · \(TradeDisplay.pnlText(summary.realizedPnL))"
        case .post(_, let post):
            return post.body
        case .clip(_, let reel):
            return reel.caption ?? "Clip"
        case .achievement(_, let achievement):
            return achievement.title
        }
    }
}
