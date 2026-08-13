import SwiftUI

/// Discovery surface pushed from Feed — not a Global Feed clone.
struct ExploreHomeView: View {
    @State private var viewModel: ExploreViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: ExploreViewModel(
                explore: data.explore,
                search: data.search,
                profiles: data.profiles,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    init(viewModel: ExploreViewModel, imagePipeline: any ImagePipeline) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
    }

    var body: some View {
        Group {
            if viewModel.isSearching {
                searchContent
            } else {
                discoveryContent
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Explore")
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search people or rooms"
        )
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.searchChanged()
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.loadIfNeeded()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitesting-explore-search") {
                viewModel.searchText = "alex"
                viewModel.searchChanged()
            }
            #endif
        }
        .accessibilityIdentifier("explore.home")
    }

    // MARK: - Discovery

    @ViewBuilder
    private var discoveryContent: some View {
        switch viewModel.phase {
        case .idle, .loading:
            if viewModel.suggestedTraders.isEmpty && viewModel.popularRooms.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("explore.loading")
            } else {
                discoveryScroll
            }
        case .failed(let message):
            if viewModel.suggestedTraders.isEmpty && viewModel.popularRooms.isEmpty {
                ExperienceErrorState(
                    title: "Couldn't load Explore",
                    message: message,
                    onRetry: { Task { await viewModel.refresh() } }
                )
            } else {
                discoveryScroll
            }
        case .loaded:
            if viewModel.showsDiscoveryEmpty {
                ExperienceEmptyState(
                    icon: .search,
                    title: "Nothing to discover yet",
                    message: "Public traders and Trade Rooms will show up here as the community grows."
                )
            } else {
                discoveryScroll
            }
        }
    }

    private var discoveryScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: ExperienceSpacing.lg) {
                if let message = viewModel.tradersFailedMessage, viewModel.suggestedTraders.isEmpty {
                    inlineSectionError(message)
                } else if !viewModel.suggestedTraders.isEmpty {
                    tradersSection
                }

                if let message = viewModel.roomsFailedMessage, viewModel.popularRooms.isEmpty {
                    inlineSectionError(message)
                } else if !viewModel.popularRooms.isEmpty {
                    roomsSection
                }

                if viewModel.isLoadingMoreTraders {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, ExperienceSpacing.sm)
                }
            }
            .padding(.top, ExperienceSpacing.sm)
            .padding(.bottom, ExperienceSpacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var tradersSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ExploreSectionHeader(
                title: "Suggested Traders",
                subtitle: "Active public profiles worth following"
            )
            .padding(.horizontal, ExperienceSpacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: ExperienceSpacing.sm) {
                    ForEach(viewModel.suggestedTraders) { trader in
                        ExploreTraderCard(
                            trader: trader,
                            imagePipeline: imagePipeline,
                            isFollowing: viewModel.isFollowing(trader),
                            onOpen: { viewModel.openTrader(trader) },
                            onToggleFollow: { viewModel.toggleFollow(trader) }
                        )
                        .onAppear {
                            if trader.id == viewModel.suggestedTraders.last?.id {
                                viewModel.loadMoreTradersIfNeeded()
                            }
                        }
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
            }
            .accessibilityIdentifier("explore.traders.rail")
        }
    }

    private var roomsSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ExploreSectionHeader(
                title: "Popular Trade Rooms",
                subtitle: "Communities ordered by membership"
            )
            .padding(.horizontal, ExperienceSpacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: ExperienceSpacing.sm) {
                    ForEach(viewModel.popularRooms) { room in
                        ExploreRoomCard(room: room) {
                            viewModel.openRoom(room)
                        }
                    }
                }
                .padding(.horizontal, ExperienceSpacing.md)
            }
            .accessibilityIdentifier("explore.rooms.rail")
        }
    }

    // MARK: - Search

    @ViewBuilder
    private var searchContent: some View {
        if viewModel.searchPhase == .searching && viewModel.searchPeople.isEmpty && viewModel.searchRooms.isEmpty {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case .failed(let message) = viewModel.searchPhase {
            ExperienceErrorState(
                title: "Search failed",
                message: message,
                onRetry: { viewModel.searchChanged() }
            )
        } else if viewModel.showsSearchEmpty {
            ExperienceEmptyState(
                icon: .search,
                title: "No matches",
                message: "Try another name, username, or Trade Room."
            )
        } else {
            List {
                if !viewModel.searchPeople.isEmpty {
                    Section("People") {
                        ForEach(viewModel.searchPeople) { trader in
                            Button {
                                viewModel.openTrader(trader)
                            } label: {
                                ExploreSearchPersonRow(
                                    trader: trader,
                                    imagePipeline: imagePipeline,
                                    isFollowing: viewModel.isFollowing(trader),
                                    onToggleFollow: { viewModel.toggleFollow(trader) }
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(colors.backgroundPrimary)
                        }
                    }
                }

                if !viewModel.searchRooms.isEmpty {
                    Section("Trade Rooms") {
                        ForEach(viewModel.searchRooms) { room in
                            Button {
                                viewModel.openRoom(room)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(room.name)
                                        .experienceStyle(.body, color: colors.primaryText)
                                    Text("\(ProfileDisplay.compactCount(room.memberCount)) members")
                                        .experienceStyle(.caption, color: colors.secondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(colors.backgroundPrimary)
                            .accessibilityIdentifier("explore.search.room.\(room.id.rawValue)")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("explore.search.results")
        }
    }

    private func inlineSectionError(_ message: String) -> some View {
        Text(message)
            .experienceStyle(.footnote, color: colors.secondaryText)
            .padding(.horizontal, ExperienceSpacing.md)
            .accessibilityIdentifier("explore.section.error")
    }
}

private struct ExploreSearchPersonRow: View {
    let trader: ExploreTraderSuggestion
    let imagePipeline: any ImagePipeline
    let isFollowing: Bool
    let onToggleFollow: () -> Void

    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: ExperienceSpacing.md) {
            FollowListAvatarView(profile: trader.profile, imagePipeline: imagePipeline, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(trader.profile.displayName)
                    .experienceStyle(.subheadline, color: colors.primaryText)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text("@\(trader.profile.username)")
                    .experienceStyle(.caption, color: colors.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: ExperienceSpacing.sm)
            Button(action: onToggleFollow) {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isFollowing ? colors.primaryText : colors.onAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(
                        Capsule().fill(isFollowing ? colors.fillSecondary : colors.accent)
                    )
            }
            .buttonStyle(.plain)
        }
        .accessibilityIdentifier("explore.search.person.\(trader.id.rawValue)")
    }
}
