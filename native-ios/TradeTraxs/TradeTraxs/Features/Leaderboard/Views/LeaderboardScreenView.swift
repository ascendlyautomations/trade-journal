import SwiftUI

/// Native Leaderboards experience pushed from Explore (Feed stack).
///
/// Filter controls stay pinned at the top (Apple Music / App Store style).
/// Only the rankings content area scrolls or swaps empty / loading / error.
struct LeaderboardScreenView: View {
    @State private var viewModel: LeaderboardScreenViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: LeaderboardScreenViewModel(
                leaderboard: data.leaderboard,
                profiles: data.profiles,
                explore: data.explore,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    init(viewModel: LeaderboardScreenViewModel, imagePipeline: any ImagePipeline) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
    }

    var body: some View {
        VStack(spacing: 0) {
            pinnedFilters
                .padding(.top, ExperienceSpacing.sm)
                .padding(.bottom, ExperienceSpacing.md)
                .background(colors.backgroundPrimary)

            contentArea
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Leaderboards")
        .toolbar(.hidden, for: .tabBar)
        .task {
            await viewModel.bootstrapIfNeeded()
        }
        .accessibilityIdentifier("leaderboard.home")
    }

    // MARK: - Pinned header (never replaced)

    private var pinnedFilters: some View {
        VStack(spacing: ExperienceSpacing.sm) {
            LeaderboardFiltersView(
                audience: viewModel.audience,
                timeframe: viewModel.timeframe,
                category: viewModel.category,
                onAudience: { viewModel.setAudience($0) },
                onTimeframe: { viewModel.setTimeframe($0) },
                onCategory: { viewModel.setCategory($0) }
            )
            if let message = viewModel.timeframeFallbackMessage {
                Text(message)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ExperienceSpacing.md)
                    .accessibilityIdentifier("leaderboard.timeframe.fallback")
            }
        }
        .accessibilityIdentifier("leaderboard.filters.pinned")
    }

    // MARK: - Scrollable / stateful content only

    @ViewBuilder
    private var contentArea: some View {
        switch viewModel.phase {
        case .idle, .loading:
            if viewModel.rows.isEmpty {
                loadingContent
            } else {
                rankingsScroll
            }
        case .failed(let message):
            if viewModel.rows.isEmpty {
                errorContent(message: message)
            } else {
                rankingsScroll
            }
        case .loaded:
            if viewModel.showsEmpty {
                emptyContent
            } else {
                rankingsScroll
            }
        }
    }

    private var rankingsScroll: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    if !viewModel.podium.isEmpty {
                        LeaderboardPodiumView(
                            podium: viewModel.podium,
                            imagePipeline: imagePipeline,
                            animateEntrance: !viewModel.state.didPlayPodiumEntrance,
                            onOpen: { viewModel.openProfile($0) },
                            onEntranceFinished: { viewModel.markPodiumEntrancePlayed() }
                        )
                    }

                    ForEach(viewModel.listRows) { row in
                        LeaderboardRowView(
                            row: row,
                            imagePipeline: imagePipeline,
                            showsFollowButton: !row.isCurrentUser,
                            onOpen: { viewModel.openProfile(row) },
                            onToggleFollow: { viewModel.toggleFollow(row) }
                        )
                        .onAppear {
                            Task { await viewModel.loadMoreIfNeeded(currentID: row.profileID) }
                        }

                        if row.profileID != viewModel.listRows.last?.profileID {
                            Divider()
                                .padding(.leading, 52 + ExperienceSpacing.md)
                                .opacity(0.35)
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, ExperienceSpacing.sm)
                    }
                }
                .padding(.bottom, viewModel.pinnedViewer == nil ? ExperienceSpacing.xl : 72)
            }
            .refreshable {
                await viewModel.refresh()
            }

            if let pinned = viewModel.pinnedViewer {
                LeaderboardPinnedUserBar(row: pinned) {
                    viewModel.openProfile(pinned)
                }
            }
        }
    }

    private var loadingContent: some View {
        ExperienceListSkeleton(style: .leaderboard)
            .accessibilityIdentifier("leaderboard.loading")
    }

    private var emptyContent: some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer(minLength: ExperienceSpacing.xl)
            ExperienceEmptyState(
                icon: .leaderboard,
                title: emptyTitle,
                message: emptyMessage
            )
            Spacer(minLength: ExperienceSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("leaderboard.empty")
    }

    private func errorContent(message: String) -> some View {
        VStack(spacing: ExperienceSpacing.lg) {
            Spacer(minLength: ExperienceSpacing.xl)
            ExperienceErrorState(
                title: "Couldn't load Leaderboards",
                message: message,
                onRetry: { Task { await viewModel.refresh() } }
            )
            Spacer(minLength: ExperienceSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("leaderboard.error")
    }

    private var emptyTitle: String {
        switch viewModel.audience {
        case .friends:
            return "No friends ranked"
        case .following:
            return "No one you follow ranked"
        case .all:
            return "No rankings yet"
        }
    }

    private var emptyMessage: String {
        switch viewModel.audience {
        case .friends:
            return "No friends have traded during this period. Try another timeframe."
        case .following:
            return "Nobody you follow ranks for this timeframe. Try All or a wider window."
        case .all:
            return "Try another timeframe or category to see traders."
        }
    }
}
