import AVFoundation
import SwiftUI

/// Permanent Clip detail destination — same hierarchy as Trade Detail.
struct ClipDetailView: View {
    @State private var viewModel: ClipDetailViewModel
    private let data: DataEnvironment
    private let navigationCoordinator: NavigationCoordinator

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showLikeHeart = false
    @State private var contentRevealed = false
    @State private var showsDeleteConfirm = false
    @State private var isDisplayingVideoFrame = false

    init(reelID: ReelID, data: DataEnvironment, navigationCoordinator: NavigationCoordinator) {
        _viewModel = State(
            initialValue: ClipDetailViewModel(
                reelID: reelID,
                feed: data.feed,
                profiles: data.profiles,
                session: data.session,
                storage: data.objectStorage,
                imagePipeline: data.imagePipeline,
                cache: data.detailCache,
                navigationCoordinator: navigationCoordinator
            )
        )
        self.data = data
        self.navigationCoordinator = navigationCoordinator
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading where viewModel.reel == nil:
                ExperienceLoadingSpinner(label: "Loading clip")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message) where viewModel.reel == nil:
                ExperienceErrorState(
                    title: "Couldn't load clip",
                    message: message,
                    onRetry: { Task { await viewModel.refresh() } }
                )
            default:
                content
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Clip")
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if viewModel.didReachEnd {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Replay") {
                        viewModel.replay()
                    }
                    .accessibilityIdentifier("detail.clip.replay")
                }
            }
        }
        .task {
            viewModel.loadIfNeeded()
            let target = InteractionTarget.reel(viewModel.reelID)
            data.engagementStore.prefetch([target])
            EngagementRealtimeSession.shared.updateRetention(
                ownerKey: "detail-reel:\(viewModel.reelID.rawValue)",
                targets: [target]
            )
            data.vaultStore.prefetch([
                VaultContentRef(contentType: .reel, contentID: viewModel.reelID.rawValue),
            ])
        }
        .onDisappear {
            EngagementRealtimeSession.shared.updateRetention(
                ownerKey: "detail-reel:\(viewModel.reelID.rawValue)",
                targets: []
            )
        }
        .experienceDetailEntry(revealed: contentRevealed, reduceMotion: reduceMotion)
        .onAppear {
            guard !contentRevealed else { return }
            ExperienceMotion.withAnimation(
                ExperienceMotion.navigation,
                reduceMotion: reduceMotion
            ) {
                contentRevealed = true
            }
        }
        .onDisappear {
            viewModel.tearDown()
        }
        .confirmationDialog(
            "Delete Clip?",
            isPresented: $showsDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Clip", role: .destructive) {
                Task {
                    _ = await viewModel.deleteReel()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.deleteErrorMessage ?? "This can’t be undone.")
        }
        .accessibilityIdentifier("detail.clip.root")
    }

    @ViewBuilder
    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let reel = viewModel.reel {
                        DetailIdentityHeader(
                            initials: viewModel.authorInitials,
                            avatar: viewModel.authorAvatar,
                            displayName: viewModel.authorDisplayName,
                            username: viewModel.authorUsername,
                            dateText: TradeDisplay.dateText(reel.createdAt),
                            isOwner: viewModel.isOwner,
                            contentLink: .reel(reel.id),
                            ownerProfileID: reel.authorProfileID,
                            shareText: {
                                let caption = reel.caption?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                if caption.isEmpty { return "Clip on TradeTraxs" }
                                return String(caption.prefix(120))
                            }(),
                            deleteTitle: "Delete Clip",
                            onDelete: viewModel.isOwner ? {
                                ExperienceHaptics.play(.warning)
                                showsDeleteConfirm = true
                            } : nil,
                            vaultRef: VaultContentRef(contentType: .reel, contentID: reel.id.rawValue),
                            accessibilityIdentifier: "detail.clip.identity"
                        )
                        .padding(.horizontal, ExperienceSpacing.lg)
                        .padding(.top, ExperienceSpacing.sm)
                        .padding(.bottom, ExperienceSpacing.md)

                        playerSection
                            .frame(maxWidth: .infinity)
                            .frame(height: min(UIScreen.main.bounds.height * 0.58, 720))
                            .background(Color.black)
                            .clipped()
                            .overlay {
                                LikeFeedbackOverlay(isVisible: showLikeHeart, reduceMotion: reduceMotion)
                            }

                        clipBody(reel, scrollProxy: proxy)
                            .padding(.horizontal, ExperienceSpacing.lg)
                            .padding(.top, ExperienceSpacing.md)
                            .padding(.bottom, ExperienceSpacing.xl)
                    }
                }
            }
        }
        .overlay {
            if viewModel.isDeleting {
                ProgressView("Deleting…")
                    .padding(ExperienceSpacing.lg)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ExperienceRadius.md))
            }
        }
    }

    private func clipBody(_ reel: Reel, scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
            EngagementBar(
                target: .reel(reel.id),
                store: data.engagementStore,
                vaultStore: data.vaultStore,
                onCommentTap: {
                    withAnimation(
                        ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion)
                    ) {
                        scrollProxy.scrollTo(Self.commentsAnchorID, anchor: .top)
                    }
                },
                vaultRef: VaultContentRef(contentType: .reel, contentID: reel.id.rawValue)
            )

            if let caption = reel.caption?.trimmingCharacters(in: .whitespacesAndNewlines),
               !caption.isEmpty
            {
                Text(caption)
                    .experienceStyle(.body, color: colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("detail.clip.caption")
            }

            if let linkedTrade {
                ClipLinkedTradeSection(
                    trade: linkedTrade,
                    style: .detailBody,
                    onOpen: { openLinkedTrade(linkedTrade.id) }
                )
                .accessibilityIdentifier("detail.clip.linkedTrade")
            }

            if viewModel.didReachEnd {
                ExperienceButton(title: "Replay", icon: .sync, kind: .secondary) {
                    viewModel.replay()
                }
            }

            CommentsSectionView(
                target: .reel(reel.id),
                contentOwnerUserID: reel.authorProfileID.rawValue,
                data: data
            )
                .id(Self.commentsAnchorID)
        }
    }

    @ViewBuilder
    private var playerSection: some View {
        ZStack {
            if let reel = viewModel.reel {
                FeedClipPosterImage(
                    thumbnail: reel.thumbnail,
                    video: reel.video,
                    imagePipeline: data.imagePipeline,
                    objectStorage: data.objectStorage,
                    contentMode: .fit,
                    allowsVideoFrameExtraction: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isDisplayingVideoFrame ? 0 : 1)
                .allowsHitTesting(false)
            } else {
                Color.black
            }

            if let player = viewModel.player {
                ClipPlayerView(
                    player: player,
                    videoGravity: viewModel.videoPresentation?.playerGravity(for: .clipsPager) ?? .resizeAspect,
                    onDoubleTapLike: {
                        presentLikeFeedback()
                        Task { await data.engagementStore.ensureLiked(on: .reel(viewModel.reelID)) }
                    },
                    onReadyForDisplayChange: { ready in
                        isDisplayingVideoFrame = ready
                    }
                )
                .accessibilityIdentifier("detail.clip.player")
            } else if viewModel.reel != nil {
                ExperienceLoadingSpinner(label: "Preparing video")
            }
        }
        .onChange(of: viewModel.player?.currentItem) { _, _ in
            isDisplayingVideoFrame = false
        }
    }

    private func presentLikeFeedback() {
        ExperienceHaptics.play(.impactLight)
        if reduceMotion {
            showLikeHeart = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 280_000_000)
                showLikeHeart = false
            }
            return
        }
        ExperienceMotion.withAnimation(MotionSpring.bouncy.animation, reduceMotion: false) {
            showLikeHeart = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 520_000_000)
            ExperienceMotion.withAnimation(
                MotionCurve.easeOut.animation(duration: .fast),
                reduceMotion: false
            ) {
                showLikeHeart = false
            }
        }
    }

    private static let commentsAnchorID = "detail.clip.comments"

    private var linkedTrade: Trade? {
        guard let reel = viewModel.reel,
              let tradeID = reel.linkedTradeID
        else { return nil }
        return data.detailCache.trade(id: tradeID)
    }

    private func openLinkedTrade(_ tradeID: TradeID) {
        navigationCoordinator.pushTradeDetail(tradeID, cache: data.detailCache)
    }
}
