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
                navigationCoordinator: navigationCoordinator,
                rpc: data.rpc,
                messages: data.messages
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
                onCategory: { viewModel.setCategory($0) },
                showCurveToggle: viewModel.canShowCurveToggle,
                isCurveMode: viewModel.displayMode == .curve,
                onToggleCurve: { viewModel.toggleDisplayMode() }
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
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                if viewModel.rows.isEmpty {
                    loadingContent
                } else {
                    primaryRankingsScroll
                }
            case .failed(let message):
                if viewModel.rows.isEmpty {
                    errorContent(message: message)
                } else {
                    primaryRankingsScroll
                }
            case .loaded:
                if viewModel.showsEmpty {
                    emptyContent
                } else {
                    primaryRankingsScroll
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var primaryRankingsScroll: some View {
        if viewModel.displayMode == .curve {
            curveRankingsScroll
        } else {
            standardRankingsScroll
        }
    }

    private var standardRankingsScroll: some View {
        rankingsScrollContent(
            rows: viewModel.listRows,
            showsPodium: true
        )
    }

    private var curveRankingsScroll: some View {
        rankingsScrollContent(
            rows: viewModel.rows,
            showsPodium: false,
            header: { curveHeader() }
        )
    }

    @ViewBuilder
    private func curveHeader() -> some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.md) {
            switch viewModel.curvePhase {
            case .idle, .loading:
                ExperienceIndeterminateProgress()
                    .frame(maxWidth: .infinity, minHeight: 120)
            case .failed(let message):
                Text(message)
                    .experienceStyle(.footnote, color: colors.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            case .loaded:
                LeaderboardCurveChartView(
                    points: viewModel.curvePoints,
                    category: viewModel.category,
                    metricFormat: viewModel.curveMetricFormat
                )
            }

            Text("Top Traders")
                .experienceStyle(.headline, color: colors.primaryText)
                .padding(.horizontal, ExperienceSpacing.md)
                .accessibilityIdentifier("leaderboard.curve.topTraders")
        }
        .padding(.horizontal, ExperienceSpacing.md)
    }

    private func rankingsScrollContent<Header: View>(
        rows: [LeaderboardRow],
        showsPodium: Bool,
        @ViewBuilder header: () -> Header = { EmptyView() }
    ) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: ExperienceSpacing.md) {
                    header()

                    if showsPodium, !viewModel.podium.isEmpty {
                        LeaderboardPodiumView(
                            podium: viewModel.podium,
                            profileFor: { viewModel.resolvedProfile(for: $0) },
                            imagePipeline: imagePipeline,
                            animateEntrance: !viewModel.state.didPlayPodiumEntrance,
                            onOpen: { viewModel.openProfile($0) },
                            onEntranceFinished: { viewModel.markPodiumEntrancePlayed() }
                        )
                    }

                    ForEach(rows) { row in
                        LeaderboardRowView(
                            row: row,
                            profile: viewModel.resolvedProfile(for: row.profileID),
                            viewerProfileID: viewModel.authenticatedProfileID,
                            imagePipeline: imagePipeline,
                            showsFollowButton: !row.isCurrentUser,
                            onOpen: { viewModel.openProfile(row) },
                            onToggleFollow: { viewModel.toggleFollow(row) }
                        )
                        .onAppear {
                            Task { await viewModel.loadMoreIfNeeded(currentID: row.profileID) }
                        }

                        if row.profileID != rows.last?.profileID {
                            Divider()
                                .padding(.leading, 32 + 44 + ExperienceSpacing.sm * 2 + ExperienceSpacing.md)
                                .opacity(0.35)
                        }
                    }

                    if viewModel.isLoadingMore {
                        ExperienceIndeterminateProgress()
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
