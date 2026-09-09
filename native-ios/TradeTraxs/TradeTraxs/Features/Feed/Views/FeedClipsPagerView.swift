import AVFoundation
import SwiftUI
import UIKit

/// Full-screen vertical Clips feed — one reel per viewport with paging snap (Reels/TikTok style).
struct FeedClipsPagerView: View {
    let entries: [FeedTimelineEntry]
    let author: (ProfileID) -> Profile?
    let imagePipeline: any ImagePipeline
    let detailCache: DetailPresentationCache
    let engagementStore: EngagementStore
    let vaultStore: VaultStore
    let playbackCoordinator: FeedVideoPlaybackCoordinator
    let isLoadingMore: Bool
    let viewerID: ProfileID?
    let onOpenAuthor: (ProfileID) -> Void
    let onOpenLinkedTrade: (TradeID) -> Void
    let onReport: (FeedTimelineEntry) -> (() -> Void)?
    let onShare: (FeedTimelineEntry) -> Void
    let onOpenDetail: (FeedTimelineEntry) -> Void
    let onLoadMore: (String) -> Void

    @State private var activeClipIndex = 0
    @State private var activeClipEntryID: String?
    @State private var commentsSheetContext: ClipsCommentsSheetContext?
    @Environment(\.themeColors) private var colors
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.scenePhase) private var scenePhase

    private var clipEntries: [FeedTimelineEntry] {
        entries.filter {
            if case .clip = $0 { return true }
            return false
        }
    }

    var body: some View {
        ZStack {
            FeedClipsVerticalPager(
                pageCount: clipEntries.count,
                activeIndex: $activeClipIndex,
                clipIDs: clipEntries.map(\.id),
                isScrollEnabled: commentsSheetContext == nil,
                makePage: { index in
                    AnyView(pageView(for: index))
                },
                onPageSettled: { index, scrollDirection in
                    handlePageBecameActive(index: index, scrollDirection: scrollDirection)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if isLoadingMore {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(colors.primaryText)
                        .padding(.vertical, ExperienceSpacing.lg)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .background(colors.primaryBackground)
        .sheet(item: $commentsSheetContext, onDismiss: {
            playbackCoordinator.setCommentsSheetPresented(false)
        }) { context in
            ReelCommentsSheetView(
                target: context.target,
                contentOwnerUserID: context.contentOwnerUserID,
                data: appEnvironment.data,
                imagePipeline: imagePipeline
            )
            .experienceSheetChrome(detents: [.medium, .large])
        }
        .onChange(of: commentsSheetContext?.id) { _, newValue in
            playbackCoordinator.setCommentsSheetPresented(newValue != nil)
            if let context = commentsSheetContext {
                playbackCoordinator.syncPlayback(for: context.reelID)
            }
        }
        .onAppear {
            if clipEntries.isEmpty {
                activeClipIndex = 0
                activeClipEntryID = nil
            } else {
                restoreActiveClipIndex()
                handlePageBecameActive(index: activeClipIndex, scrollDirection: 1)
            }
        }
        .onChange(of: clipEntries.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                activeClipIndex = 0
                activeClipEntryID = nil
                return
            }
            restoreActiveClipIndex()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            handlePageBecameActive(index: activeClipIndex, scrollDirection: 1)
        }
        .accessibilityIdentifier("feed.clips.pager")
    }

    @ViewBuilder
    private func pageView(for index: Int) -> some View {
        if clipEntries.indices.contains(index) {
            let entry = clipEntries[index]
            FeedClipsPageHostRoot(index: index) {
                FeedClipsPageView(
                    entry: entry,
                    author: author(entry.authorProfileID),
                    imagePipeline: imagePipeline,
                    detailCache: detailCache,
                    engagementStore: engagementStore,
                    vaultStore: vaultStore,
                    playbackCoordinator: playbackCoordinator,
                    viewerID: viewerID,
                    onOpenAuthor: { onOpenAuthor(entry.authorProfileID) },
                    onOpenComments: { presentCommentsSheet(for: entry) },
                    onOpenLinkedTrade: onOpenLinkedTrade,
                    onReport: onReport(entry),
                    onShare: { onShare(entry) },
                    onOpenDetail: { onOpenDetail(entry) }
                )
            }
        } else {
            Color.black
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
    }

    private func restoreActiveClipIndex() {
        let ids = clipEntries.map(\.id)
        if let activeClipEntryID, let preservedIndex = ids.firstIndex(of: activeClipEntryID) {
            activeClipIndex = preservedIndex
            return
        }
        activeClipIndex = min(activeClipIndex, max(0, ids.count - 1))
    }

    private func handlePageBecameActive(index: Int, scrollDirection: Int) {
        guard clipEntries.indices.contains(index) else { return }
        let entry = clipEntries[index]
        activeClipEntryID = entry.id
        activateEntry(entry, atIndex: index)
        prefetchNeighborClip(from: index, scrollDirection: scrollDirection)
        onLoadMore(entry.id)
        if index >= clipEntries.count - 2 {
            onLoadMore(clipEntries.last?.id ?? entry.id)
        }
    }

    private func prefetchNeighborClip(from index: Int, scrollDirection: Int) {
        let direction = scrollDirection >= 0 ? 1 : -1
        let neighborIndex = index + direction
        guard clipEntries.indices.contains(neighborIndex),
              case .clip(_, let reel) = clipEntries[neighborIndex]
        else { return }
        playbackCoordinator.prepareNeighborClip(reel, atIndex: neighborIndex)
    }

    private func presentCommentsSheet(for entry: FeedTimelineEntry) {
        guard case .clip(_, let reel) = entry else { return }
        ExperienceHaptics.play(.selection)
        commentsSheetContext = ClipsCommentsSheetContext(
            entryID: entry.id,
            target: entry.interactionTarget,
            contentOwnerUserID: entry.authorProfileID.rawValue,
            reelID: reel.id
        )
        playbackCoordinator.setCommentsSheetPresented(true)
        playbackCoordinator.syncPlayback(for: reel.id)
    }

    private func activateEntry(_ entry: FeedTimelineEntry, atIndex index: Int) {
        guard case .clip(_, let reel) = entry else { return }
        playbackCoordinator.setActiveClip(reel, atIndex: index)
    }
}

private struct ClipsCommentsSheetContext: Identifiable {
    let entryID: String
    let target: InteractionTarget
    let contentOwnerUserID: String
    let reelID: ReelID

    var id: String { entryID }
}

// MARK: - Overlay layout tokens

private enum FeedClipsOverlayLayout {
    static let horizontalPadding: CGFloat = 16
    static let actionRailWidth: CGFloat = 52
    static let metadataActionGap: CGFloat = 12
    static let actionItemSpacing: CGFloat = 18
    static let actionIconPointSize: CGFloat = 24
    /// Single tunable lift for the entire Clip overlay — metadata + action rail move together.
    static let clipOverlayBottomPadding: CGFloat = 15
    static let gradientHeight: CGFloat = 280
}

// MARK: - Single clip page

private struct FeedClipsPageView: View {
    let entry: FeedTimelineEntry
    let author: Profile?
    let imagePipeline: any ImagePipeline
    let detailCache: DetailPresentationCache
    @Bindable var engagementStore: EngagementStore
    @Bindable var vaultStore: VaultStore
    let playbackCoordinator: FeedVideoPlaybackCoordinator
    let viewerID: ProfileID?
    let onOpenAuthor: () -> Void
    let onOpenComments: () -> Void
    let onOpenLinkedTrade: (TradeID) -> Void
    let onReport: (() -> Void)?
    let onShare: () -> Void
    let onOpenDetail: () -> Void

    @Bindable private var followCoordinator = FollowMutationCoordinator.shared
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.themeColors) private var colors
    @State private var followInFlight = false
    @State private var showsVaultSheet = false

    private var vaultRef: VaultContentRef? { VaultContentRef.from(entry.interactionTarget) }
    private var isVaulted: Bool {
        guard let vaultRef else { return false }
        return vaultStore.state(for: vaultRef).isVaulted
    }

    private var reel: Reel? {
        if case .clip(_, let reel) = entry { return reel }
        return nil
    }

    private var linkedTrade: Trade? {
        FeedLinkedContentResolver.linkedTrade(for: entry, cache: detailCache)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black

            if let reel {
                clipMedia(reel: reel)

                clipsBottomGradient

                clipOverlayBottom(reel: reel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
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

    private var clipsBottomGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.12), location: 0.35),
                .init(color: .black.opacity(0.52), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: FeedClipsOverlayLayout.gradientHeight)
        .allowsHitTesting(false)
    }

    /// Unified bottom overlay — metadata and action rail share one bottom boundary.
    private func clipOverlayBottom(reel: Reel) -> some View {
        HStack(alignment: .bottom, spacing: FeedClipsOverlayLayout.metadataActionGap) {
            clipMetadata(reel: reel)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            clipActionRail(reel: reel)
                .fixedSize(horizontal: true, vertical: true)
        }
        .padding(.horizontal, FeedClipsOverlayLayout.horizontalPadding)
        .padding(.bottom, FeedClipsOverlayLayout.clipOverlayBottomPadding)
    }

    @ViewBuilder
    private func clipMedia(reel: Reel) -> some View {
        let presentation = playbackCoordinator.presentation(for: reel.id)
        let gravity = presentation?.playerGravity(for: .clipsPager) ?? .resizeAspectFill
        let posterMode = presentation?.swiftUIPosterContentMode(for: .clipsPager) ?? .fill

        ZStack {
            FeedClipPosterImage(
                reference: reel.thumbnail ?? reel.video,
                imagePipeline: imagePipeline,
                contentMode: posterMode
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)

            if playbackCoordinator.isActive(reel.id),
               let player = playbackCoordinator.player(for: reel.id)
            {
                FeedInlineVideoSurface(player: player, videoGravity: gravity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            if playbackCoordinator.shouldShowPlayIndicator(for: reel.id) {
                ExperienceIcon(icon: .play, size: .xl, color: .white)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                    .allowsHitTesting(false)
            }

            Color.clear
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.trailing, FeedClipsOverlayLayout.actionRailWidth + FeedClipsOverlayLayout.horizontalPadding + FeedClipsOverlayLayout.metadataActionGap)
                .experienceDoubleTapLike(
                    target: entry.interactionTarget,
                    store: engagementStore,
                    anchorsHeartToTapLocation: true,
                    onSingleTap: {
                        playbackCoordinator.togglePlayPause(for: reel)
                    }
                )
                .accessibilityLabel("Play or pause clip")
                .accessibilityAddTraits(.isButton)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private func clipMetadata(reel: Reel) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            HStack(spacing: ExperienceSpacing.sm) {
                Button(action: onOpenAuthor) {
                    HStack(spacing: ExperienceSpacing.sm) {
                        FollowListAvatarView(
                            profile: resolvedProfile,
                            imagePipeline: imagePipeline,
                            size: 32
                        )
                        Text(authorPrimaryLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showsFollowButton {
                    followChip
                }
            }

            if showsSecondaryUsername {
                Text(secondaryUsernameLabel)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }

            if let caption = entry.feedCaptionText {
                FeedCaptionPreview(
                    text: caption,
                    lineLimit: FeedCaptionLineLimit.clip,
                    style: .clipsOverlay,
                    onSeeMore: onOpenDetail,
                    seeMoreAccessibilityIdentifier: "feed.clips.seeMore"
                )
            }

            if let linkedTrade {
                ClipLinkedTradeSection(
                    trade: linkedTrade,
                    style: .clipsOverlay,
                    onOpen: { onOpenLinkedTrade(linkedTrade.id) }
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func clipActionRail(reel: Reel) -> some View {
        let snap = engagementStore.snapshot(for: entry.interactionTarget)

        VStack(spacing: FeedClipsOverlayLayout.actionItemSpacing) {
            FeedClipsActionRailItem(
                systemName: snap.viewerHasLiked ? "heart.fill" : "heart",
                label: snap.viewerHasLiked ? "Unlike" : "Like",
                value: snap.likeCount > 0 ? LikeButton.formatCount(snap.likeCount) : nil,
                iconColor: snap.viewerHasLiked ? .red : .white
            ) {
                Task { await engagementStore.toggleLike(on: entry.interactionTarget) }
            }

            FeedClipsActionRailItem(
                systemName: "bubble.right.fill",
                label: "Comments",
                value: snap.commentCount > 0 ? LikeButton.formatCount(snap.commentCount) : nil
            ) {
                onOpenComments()
            }

            FeedClipsActionRailItem(
                systemName: "square.and.arrow.up",
                label: "Share"
            ) {
                onShare()
            }

            if let vaultRef {
                FeedClipsActionRailItem(
                    systemName: vaultStore.state(for: vaultRef).isVaulted ? "hexagon.fill" : "hexagon",
                    label: vaultStore.state(for: vaultRef).isVaulted ? "Manage in Vault" : "Add to Vault",
                    iconColor: vaultStore.state(for: vaultRef).isVaulted ? colors.accent : .white
                ) {
                    openVaultSheet()
                }
            }

            FeedClipsActionRailItem(
                systemName: playbackCoordinator.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: playbackCoordinator.isMuted ? "Unmute" : "Mute"
            ) {
                playbackCoordinator.toggleMute()
            }

            ContentOverflowMenu(
                isOwner: viewerID == entry.authorProfileID,
                onReport: onReport,
                onAddToVault: vaultRef == nil ? nil : { openVaultSheet() },
                onManageInVault: vaultRef == nil || !isVaulted ? nil : { openVaultSheet() },
                foregroundColor: .white,
                accessibilityIdentifier: "feed.clips.overflow.\(entry.id)"
            )
            .frame(width: FeedClipsOverlayLayout.actionRailWidth)
        }
        .frame(width: FeedClipsOverlayLayout.actionRailWidth)
    }

    private var followChip: some View {
        Button {
            followAuthor()
        } label: {
            Text("Follow")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 28)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.22))
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(followInFlight)
        .accessibilityLabel("Follow")
    }

    private var showsFollowButton: Bool {
        guard let viewerID else { return false }
        guard viewerID != entry.authorProfileID else { return false }
        guard followCoordinator.isFollowRelationshipResolved(
            viewer: viewerID,
            target: entry.authorProfileID
        ) else { return false }
        return !resolvedIsFollowing
    }

    private var resolvedIsFollowing: Bool {
        guard let viewerID else { return false }
        _ = followCoordinator.revision
        return followCoordinator.isFollowing(viewer: viewerID, target: entry.authorProfileID)
    }

    private func followAuthor() {
        guard let viewerID, !followInFlight, !resolvedIsFollowing else { return }
        ExperienceHaptics.play(.selection)
        followInFlight = true
        followCoordinator.applyEdgeChange(
            viewer: viewerID,
            target: entry.authorProfileID,
            isFollowing: true
        )

        Task {
            defer { followInFlight = false }
            do {
                try await appEnvironment.data.profiles.follow(from: viewerID, to: entry.authorProfileID)
            } catch {
                followCoordinator.applyEdgeChange(
                    viewer: viewerID,
                    target: entry.authorProfileID,
                    isFollowing: false
                )
            }
        }
    }

    private var resolvedProfile: Profile {
        if let author { return author }
        return Profile(
            id: entry.authorProfileID,
            userID: UserID(entry.authorProfileID.rawValue),
            username: "",
            displayName: "User",
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private var normalizedUsername: String {
        author?.username
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased() ?? ""
    }

    private var normalizedDisplayName: String {
        let raw = author?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.replacingOccurrences(of: "@", with: "").lowercased()
    }

    private var authorPrimaryLabel: String {
        let username = author?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let display = author?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !username.isEmpty {
            if display.isEmpty || normalizedDisplayName == normalizedUsername {
                return username.hasPrefix("@") ? username : "@\(username)"
            }
            return display
        }

        if !display.isEmpty { return display }
        return "User"
    }

    private var showsSecondaryUsername: Bool {
        let username = author?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !username.isEmpty else { return false }
        let handle = username.hasPrefix("@") ? username : "@\(username)"
        return authorPrimaryLabel != handle
    }

    private var secondaryUsernameLabel: String {
        let username = author?.username.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return username.hasPrefix("@") ? username : "@\(username)"
    }
}

// MARK: - Action rail controls

private struct FeedClipsActionRailItem: View {
    let systemName: String
    let label: String
    var value: String? = nil
    var iconColor: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FeedClipsActionRailLabel(
                systemName: systemName,
                label: label,
                value: value,
                iconColor: iconColor
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FeedClipsActionRailLabel: View {
    let systemName: String
    let label: String
    var value: String? = nil
    var iconColor: Color = .white

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: systemName)
                .font(.system(size: FeedClipsOverlayLayout.actionIconPointSize, weight: .semibold))
                .foregroundStyle(iconColor)
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                .frame(width: ExperienceAccessibility.minTouchTarget, height: 32)

            if let value {
                Text(value)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .frame(minHeight: 12)
            }
        }
        .frame(width: FeedClipsOverlayLayout.actionRailWidth)
        .accessibilityLabel(label)
    }
}

/// UIKit share sheet wrapper for clip URLs.
private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
