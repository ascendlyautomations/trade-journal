import SwiftUI

/// Permanent Clip detail destination — same hierarchy as Trade Detail.
struct ClipDetailView: View {
    @State private var viewModel: ClipDetailViewModel
    private let data: DataEnvironment

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showLikeHeart = false
    @State private var contentRevealed = false
    @State private var showsDeleteConfirm = false

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
            data.engagementStore.prefetch([.reel(viewModel.reelID)])
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
                onCommentTap: {
                    withAnimation(
                        ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion)
                    ) {
                        scrollProxy.scrollTo(Self.commentsAnchorID, anchor: .top)
                    }
                }
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
        if let player = viewModel.player {
            ClipPlayerView(
                player: player,
                onDoubleTapLike: {
                    presentLikeFeedback()
                    Task { await data.engagementStore.ensureLiked(on: .reel(viewModel.reelID)) }
                }
            )
            .accessibilityIdentifier("detail.clip.player")
        } else {
            ZStack {
                Color.black
                ExperienceLoadingSpinner(label: "Preparing video")
            }
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
}
