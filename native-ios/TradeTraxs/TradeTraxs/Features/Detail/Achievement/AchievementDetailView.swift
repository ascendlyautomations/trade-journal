import SwiftUI

/// Permanent Achievement detail destination, same hierarchy as Trade Detail.
struct AchievementDetailView: View {
    @State private var viewModel: AchievementDetailViewModel
    @State private var contentRevealed = false
    @State private var showsDeleteConfirm = false
    @State private var showsShareSheet = false
    private let imagePipeline: any ImagePipeline
    private let data: DataEnvironment

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        achievementID: AchievementID,
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: AchievementDetailViewModel(
                achievementID: achievementID,
                achievements: data.achievements,
                profiles: data.profiles,
                session: data.session,
                imagePipeline: data.imagePipeline,
                cache: data.detailCache,
                navigationCoordinator: navigationCoordinator
            )
        )
        self.imagePipeline = data.imagePipeline
        self.data = data
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading where viewModel.achievement == nil:
                ExperienceLoadingOverlay(label: "Loading achievement")
            case .failed(let failure) where viewModel.achievement == nil:
                ExperienceErrorState(
                    title: failure.title,
                    message: failure.message,
                    onRetry: failure.isRetryable ? { Task { await viewModel.refresh() } } : nil
                )
            default:
                content
            }
        }
        .experienceScreenBackground()
        .onAppear {
            engagementTarget(forRouteID: viewModel.achievementID)
                .recordCreatorImpression(surface: "detail")
        }
        .experienceNavigationTitle(viewModel.achievement?.title ?? "Achievement")
        .liveVoiceTopSessionChrome()
        .toolbar(.hidden, for: .tabBar)
        .task {
            viewModel.loadIfNeeded()
            let target = engagementTarget(forRouteID: viewModel.achievementID)
            data.engagementStore.prefetch([target])
            data.vaultStore.prefetch([
                vaultRef(forAchievementID: viewModel.achievementID),
            ])
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
        .confirmationDialog(
            "Delete Achievement?",
            isPresented: $showsDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Achievement", role: .destructive) {
                Task {
                    _ = await viewModel.deleteAchievement()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the achievement.")
        }
        .alert(
            "Couldn't delete achievement",
            isPresented: Binding(
                get: { viewModel.deleteErrorMessage != nil },
                set: { if !$0 { viewModel.clearDeleteError() } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.deleteErrorMessage ?? "")
        }
        .sheet(isPresented: $showsShareSheet) {
            if let achievement = viewModel.achievement,
               let url = DetailContentLink.achievement(achievement.id).url
            {
                AchievementDetailShareSheet(
                    items: ["\(achievement.title) on TradeTraxs", url]
                )
            }
        }
        .accessibilityIdentifier("detail.achievement.root")
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let achievement = viewModel.achievement {
                CommentsDetailChrome(
                    target: engagementTarget(for: achievement),
                    contentOwnerUserID: achievement.ownerProfileID.rawValue,
                    data: data
                ) { commentsVM, currentUserID, _ in
                    achievementScroll(
                        achievement: achievement,
                        commentsVM: commentsVM,
                        currentUserID: currentUserID
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func achievementScroll(
        achievement: Achievement,
        commentsVM: CommentsViewModel,
        currentUserID: ProfileID?
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                        DetailIdentityHeader(
                            initials: viewModel.authorInitials,
                            avatar: viewModel.authorAvatar,
                            displayName: viewModel.authorDisplayName,
                            username: viewModel.authorUsername,
                            dateText: TradeDisplay.dateText(achievement.achievedAt),
                            isOwner: viewModel.isOwner,
                            contentLink: .achievement(achievement.id),
                            ownerProfileID: achievement.ownerProfileID,
                            shareText: "\(achievement.title) on TradeTraxs",
                            deleteTitle: "Delete Achievement",
                            onDelete: viewModel.isOwner && !viewModel.isDeleting
                                ? {
                                    ExperienceHaptics.play(.warning)
                                    showsDeleteConfirm = true
                                }
                                : nil,
                            onOpenAuthor: { viewModel.openAuthor() },
                            vaultRef: vaultRef(for: achievement),
                            accessibilityIdentifier: "detail.achievement.identity"
                        )
                        .padding(.horizontal, ExperienceSpacing.lg)
                        .padding(.top, ExperienceSpacing.sm)
                        .padding(.bottom, ExperienceSpacing.md)

                        if achievementHasAttachedImage(achievement) {
                            InteractiveImageView(
                                mediaID: achievement.id.rawValue,
                                reference: achievement.image,
                                purpose: .postImage,
                                imagePipeline: imagePipeline,
                                emptyIcon: .leaderboard,
                                accessibilityIdentifier: "detail.achievement.media",
                                deliveryQuality: .fullResolution,
                                auditSurface: "detail",
                                onDoubleTapLike: {
                                    Task {
                                        if let achievement = viewModel.achievement {
                                            await data.engagementStore.ensureLiked(
                                                on: engagementTarget(for: achievement)
                                            )
                                        }
                                    }
                                }
                            )
                            achievementEngagementBar(achievement, scrollProxy: proxy)
                                .padding(.horizontal, ExperienceSpacing.lg)
                                .padding(.top, ExperienceSpacing.xxs)

                            PublicAchievementContentStack(
                                achievement: achievement,
                                showsInlineNotes: true,
                                showsFeaturedTag: true
                            )
                            .padding(.horizontal, ExperienceSpacing.lg)
                            .padding(.top, ExperienceSpacing.sm)
                            .accessibilityIdentifier("detail.achievement.content")
                        }

                        achievementBody(
                            achievement,
                            scrollProxy: proxy,
                            showsMediaEngagement: achievementHasAttachedImage(achievement),
                            commentsVM: commentsVM,
                            currentUserID: currentUserID
                        )
                            .padding(.horizontal, ExperienceSpacing.lg)
                            .padding(
                                .top,
                                achievementHasAttachedImage(achievement)
                                    ? ExperienceSpacing.md
                                    : ExperienceSpacing.sm
                            )
                            .padding(.bottom, ExperienceSpacing.xl)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .commentThreadScrollSupport(
                viewModel: commentsVM,
                scrollProxy: proxy,
                reduceMotion: reduceMotion
            )
            .detailCommentsScrollOnOpen(
                intent: .achievement(viewModel.achievementID),
                anchorID: Self.commentsAnchorID,
                isContentReady: true,
                contentRevealed: contentRevealed,
                detailCache: data.detailCache,
                scrollProxy: proxy,
                reduceMotion: reduceMotion
            )
        }
    }

    private func achievementBody(
        _ achievement: Achievement,
        scrollProxy: ScrollViewProxy,
        showsMediaEngagement: Bool,
        commentsVM: CommentsViewModel,
        currentUserID: ProfileID?
    ) -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            if !showsMediaEngagement {
                PublicAchievementContentStack(
                    achievement: achievement,
                    showsInlineNotes: true,
                    showsFeaturedTag: true
                )
                .accessibilityIdentifier("detail.achievement.content")
                achievementEngagementBar(achievement, scrollProxy: scrollProxy)
            }

            CommentsSectionView(
                viewModel: commentsVM,
                currentUserID: currentUserID,
                imagePipeline: imagePipeline
            )
            .id(Self.commentsAnchorID)
        }
    }

    private func achievementEngagementBar(
        _ achievement: Achievement,
        scrollProxy: ScrollViewProxy
    ) -> some View {
        EngagementBar(
            target: engagementTarget(for: achievement),
            store: data.engagementStore,
            vaultStore: data.vaultStore,
            onCommentTap: {
                withAnimation(
                    ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion)
                ) {
                    scrollProxy.scrollTo(Self.commentsAnchorID, anchor: .top)
                }
            },
            onShareTap: { showsShareSheet = true },
            vaultRef: vaultRef(for: achievement)
        )
    }

    private static let commentsAnchorID = "detail.achievement.comments"

    private func achievementHasAttachedImage(_ achievement: Achievement) -> Bool {
        guard let image = achievement.image else { return false }
        return !image.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func vaultRef(for achievement: Achievement) -> VaultContentRef {
        vaultRef(forAchievementID: achievement.id)
    }

    /// Feed rows vault the achievement post. Detail uses that same key when it was opened from the feed.
    private func vaultRef(forAchievementID achievementID: AchievementID) -> VaultContentRef {
        let target = engagementTarget(forRouteID: achievementID)
        return VaultContentRef.from(target)
            ?? VaultContentRef(contentType: .achievement, contentID: achievementID.rawValue)
    }

    private func engagementTarget(forRouteID achievementID: AchievementID) -> InteractionTarget {
        data.detailCache.feedEngagementTarget(forAchievement: achievementID)
            ?? .achievement(achievementID)
    }

    private func engagementTarget(for achievement: Achievement) -> InteractionTarget {
        data.detailCache.feedEngagementTarget(forAchievement: achievement.id)
            ?? .achievement(achievement.id)
    }

}

private struct AchievementDetailShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
