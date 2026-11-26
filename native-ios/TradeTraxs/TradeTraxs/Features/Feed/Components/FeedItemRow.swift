import SwiftUI

/// Instagram-style continuous feed row, media-first when media exists, text-first otherwise.
struct FeedItemRow: View {
    let entry: FeedTimelineEntry
    let author: Profile?
    let imagePipeline: any ImagePipeline
    let engagementStore: EngagementStore
    let vaultStore: VaultStore
    let detailCache: DetailPresentationCache
    let playbackCoordinator: FeedVideoPlaybackCoordinator
    let onOpen: () -> Void
    let onOpenComments: () -> Void
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

    /// Linked clip pill on row media, skip the footer embed when already on-image.
    private var showsLinkedClipOnTradeImage: Bool {
        guard linkedReel != nil, entry.hasDisplayMedia else { return false }
        switch entry {
        case .trade, .post:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func feedLinkedClipImageOverlay(for reel: Reel) -> some View {
        FeedLinkedClipImageOverlay(
            reel: reel,
            imagePipeline: imagePipeline,
            onOpen: { onOpenLinkedClip(reel.id) },
            accessibilityIdentifier: "feed.trade.linkedClip.overlay.\(reel.id.rawValue)"
        )
        .padding(ExperienceSpacing.sm)
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
                feedCommentTapAction()
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

    /// Media-first rows, engagement attached directly under media, caption below.
    private var standardMediaLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            feedImageMedia
            mediaFooter
        }
    }

    private var mediaFooter: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            engagement
            if case .trade(_, let summary) = entry {
                tradePostDetails(summary, opensOnTap: true)
            } else if case .achievement(_, let achievement) = entry {
                achievementPostDetails(achievement, opensOnTap: true)
            } else {
                summary
            }
            feedCaptionPreview
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
            roomShareCard
            linkedEmbeds
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.top, ExperienceSpacing.xxs)
        .padding(.bottom, ExperienceSpacing.sm)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
        }
    }

    // MARK: - Layout B (text-only, body opens; like-row buttons stay independent)

    private var textLayout: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if case .trade(_, let summary) = entry {
                engagement
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    tradePostDetails(summary)
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
            } else if case .achievement(_, let achievement) = entry {
                engagement
                VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
                    achievementPostDetails(achievement)
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
            } else {
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

                roomShareCard
                engagement
            }
        }
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.bottom, ExperienceSpacing.md)
    }

    // MARK: - Media (full bleed, only when hasDisplayMedia)

    @ViewBuilder
    private var feedImageMedia: some View {
        switch entry {
        case .trade(_, let summary):
            ZStack(alignment: .bottomTrailing) {
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

                if let linkedReel {
                    feedLinkedClipImageOverlay(for: linkedReel)
                }
            }

        case .post(_, let post):
            let mediaItems = post.media.filter {
                !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if mediaItems.count == 1, let first = mediaItems.first {
                ZStack(alignment: .bottomTrailing) {
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

                    if let linkedReel {
                        feedLinkedClipImageOverlay(for: linkedReel)
                    }
                }
            } else if mediaItems.count > 1 {
                ZStack(alignment: .bottomTrailing) {
                    TabView {
                        ForEach(Array(mediaItems.enumerated()), id: \.offset) { index, media in
                            InteractiveImageView(
                                mediaID: "\(entry.id)-\(index)",
                                reference: media,
                                purpose: .postImage,
                                imagePipeline: imagePipeline,
                                emptyIcon: .photo,
                                accessibilityIdentifier: "feed.post.media.\(index)",
                                deliveryQuality: .feedDisplay,
                                auditSurface: "feed",
                                onSingleTap: onOpen,
                                onDoubleTapLike: {
                                    Task { await engagementStore.ensureLiked(on: entry.interactionTarget) }
                                }
                            )
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 200)
                    .accessibilityIdentifier("feed.post.media")

                    if let linkedReel {
                        feedLinkedClipImageOverlay(for: linkedReel)
                    }
                }
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
        if let linkedReel, !showsLinkedClipOnTradeImage {
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

    private var feedCommentTapAction: () -> Void {
        switch entry {
        case .trade, .post, .achievement:
            return onOpenComments
        case .clip:
            return onOpen
        }
    }

    // MARK: - Engagement

    @ViewBuilder
    private var engagement: some View {
        EngagementBar(
            target: entry.interactionTarget,
            store: engagementStore,
            vaultStore: vaultStore,
            onCommentTap: feedCommentTapAction,
            onShareTap: onShare,
            onEmptyAreaTap: onOpen,
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
        case .achievement:
            EmptyView()
        }
    }

    private func tradeSummary(_ summary: TradeSummary) -> some View {
        tradeMetrics(summary)
    }

    /// Trade metrics and copy-trade metadata, always below the engagement row.
    @ViewBuilder
    private func tradePostDetails(_ summary: TradeSummary, opensOnTap: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            tradeMetrics(summary, opensOnTap: opensOnTap)
            if summary.mode == .copyTraded {
                copyTradeFeedFooter(summary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .feedOpensOnTap(opensOnTap, action: onOpen)
            }
        }
    }

    private func feedAccountProviderName(for summary: TradeSummary) -> String? {
        guard let trade = detailCache.trade(id: summary.id),
              let accountID = trade.accountID
        else { return nil }
        return detailCache.accountName(for: accountID)
    }

    private func tradeMetrics(_ summary: TradeSummary, opensOnTap: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            PublicTradeHeadlineRow(
                ticker: summary.symbol.ticker,
                realizedPnL: summary.realizedPnL
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .feedOpensOnTap(opensOnTap, action: onOpen)
            .accessibilityIdentifier("feed.trade.headline")

            PublicTradeMetaChipRow(
                summary: summary,
                showsSession: summary.mode != .copyTraded,
                accountProviderName: feedAccountProviderName(for: summary)
            )
                .accessibilityIdentifier("feed.trade.badges")
                .feedOpensOnTap(opensOnTap, allowsSiblingScroll: true, action: onOpen)
        }
    }

    @ViewBuilder
    private func achievementPostDetails(_ achievement: Achievement, opensOnTap: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            PublicAchievementHeadlineRow(achievement: achievement)
                .frame(maxWidth: .infinity, alignment: .leading)
                .feedOpensOnTap(opensOnTap, action: onOpen)
                .accessibilityIdentifier("feed.achievement.headline")

            PublicAchievementMetaChipRow(achievement: achievement)
                .feedOpensOnTap(opensOnTap, allowsSiblingScroll: true, action: onOpen)
                .accessibilityIdentifier("feed.achievement.badges")
        }
    }

    private func copyTradeFeedFooter(_ summary: TradeSummary) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.xxs) {
            copyTradedSummaryText(
                modeSuffix: CopyTradePresentation.modeCountSegment(
                    fromPublicSummary: summary.copyTradePublicModeSummary
                )
            )
            .foregroundStyle(colors.primaryText)
            .lineLimit(2)
            .accessibilityIdentifier("feed.trade.copyTradedTitle")

            Text(
                TradeDisplay.feedCopyExecutionMetadata(
                    entryAt: summary.entryAt,
                    exitAt: summary.exitAt
                )
            )
            .experienceStyle(.caption, color: colors.secondaryText)
            .lineLimit(2)
            .accessibilityIdentifier("feed.trade.copyExecutionTiming")
        }
    }

    private func copyTradedSummaryText(modeSuffix: String?) -> Text {
        let title = Text("Copy Traded")
            .font(ExperienceTypography.font(.caption))
            .fontWeight(.semibold)
        guard let modeSuffix, !modeSuffix.isEmpty else { return title }
        let modes = Text(" • \(modeSuffix)")
            .font(ExperienceTypography.font(.caption))
            .fontWeight(.regular)
        return title + modes
    }

    // MARK: - Caption

    @ViewBuilder
    private var roomShareCard: some View {
        if case .post(_, let post) = entry, let share = post.roomShare {
            FeedRoomShareCard(share: share)
        }
    }

    @ViewBuilder
    private var feedCaptionPreview: some View {
        if let text = entry.feedCaptionText,
           let lineLimit = entry.feedCaptionLineLimit
        {
            FeedCaptionPreview(
                text: text,
                lineLimit: lineLimit,
                seeMoreAccessibilityIdentifier: isImagePostRow
                    ? "feed.post.seeMore"
                    : "feed.caption.seeMore"
            )
        }
    }
}

private extension View {
    /// Opens the feed item on a tap. Scrollable rows use a simultaneous tap so a drag still scrolls.
    @ViewBuilder
    func feedOpensOnTap(
        _ isEnabled: Bool,
        allowsSiblingScroll: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if !isEnabled {
            self
        } else if allowsSiblingScroll {
            self.simultaneousGesture(TapGesture().onEnded { action() })
        } else {
            self
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
        }
    }
}

/// Lightweight feed context-menu preview, cached entry data only.
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
            return ReelCaptionDisplay.displayText(for: reel)
        case .achievement(_, let achievement):
            return achievement.title
        }
    }
}
