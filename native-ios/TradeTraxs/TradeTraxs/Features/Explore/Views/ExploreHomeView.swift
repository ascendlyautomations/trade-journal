import SwiftUI
import UIKit

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
                navigationCoordinator: navigationCoordinator,
                rpc: data.rpc
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
        .confirmationDialog(
            "Unfollow @\(viewModel.pendingUnfollow?.profile.username ?? "")?",
            isPresented: Binding(
                get: { viewModel.pendingUnfollow != nil },
                set: { if !$0 { viewModel.pendingUnfollow = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Unfollow", role: .destructive) {
                viewModel.confirmUnfollow()
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingUnfollow = nil
            }
        }
        .accessibilityIdentifier("explore.home")
    }

    // MARK: - Discovery

    @ViewBuilder
    private var discoveryContent: some View {
        switch viewModel.phase {
        case .idle, .loading:
            if viewModel.suggestedTraders.isEmpty && viewModel.popularRooms.isEmpty {
                ExperienceListSkeleton(style: .explore)
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
                leaderboardsSection

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

    private var leaderboardsSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ExploreSectionHeader(
                title: "Leaderboards",
                subtitle: "Rankings across the community"
            )
            .padding(.horizontal, ExperienceSpacing.md)

            LeaderboardExploreCard {
                viewModel.openLeaderboards()
            }
        }
        .accessibilityIdentifier("explore.leaderboards.section")
    }

    private var tradersSection: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ExploreSectionHeader(
                title: "Suggested Traders",
                subtitle: "Active public profiles worth following",
                trailingTitle: "View More",
                onTrailing: { viewModel.openSuggestedTraders() }
            )
            .padding(.horizontal, ExperienceSpacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: ExperienceSpacing.sm) {
                    ForEach(viewModel.suggestedTraders) { trader in
                        ExploreTraderCard(
                            trader: trader,
                            profile: viewModel.resolvedProfile(for: trader),
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
                        ExploreRoomCard(room: room, imagePipeline: imagePipeline) {
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
                                ExploreTraderListRow(
                                    trader: trader,
                                    profile: viewModel.resolvedProfile(for: trader),
                                    imagePipeline: imagePipeline,
                                    isFollowing: viewModel.isFollowing(trader),
                                    onToggleFollow: { viewModel.toggleFollow(trader) }
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(colors.backgroundPrimary)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if viewModel.isFollowing(trader) {
                                    Button(role: .destructive) {
                                        viewModel.toggleFollow(trader)
                                    } label: {
                                        Label("Unfollow", systemImage: "person.badge.minus")
                                    }
                                } else {
                                    Button {
                                        viewModel.toggleFollow(trader)
                                    } label: {
                                        Label("Follow", systemImage: "person.badge.plus")
                                    }
                                    .tint(colors.accent)
                                }
                            }
                            .contextMenu {
                                Button {
                                    viewModel.openTrader(trader)
                                } label: {
                                    Label("View Profile", systemImage: "person.crop.circle")
                                }
                                Button {
                                    UIPasteboard.general.string = "@\(trader.profile.username)"
                                    ExperienceHaptics.play(.success)
                                } label: {
                                    Label("Copy Username", systemImage: "doc.on.doc")
                                }
                                Button {
                                    viewModel.toggleFollow(trader)
                                } label: {
                                    Label(
                                        viewModel.isFollowing(trader) ? "Unfollow" : "Follow",
                                        systemImage: viewModel.isFollowing(trader)
                                            ? "person.badge.minus"
                                            : "person.badge.plus"
                                    )
                                }
                            }
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
                                    if let memberCount = room.memberCount {
                                        Text("\(ProfileDisplay.compactCount(memberCount)) members")
                                            .experienceStyle(.caption, color: colors.secondaryText)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(colors.backgroundPrimary)
                            .contextMenu {
                                Button {
                                    viewModel.openRoom(room)
                                } label: {
                                    Label("Open", systemImage: "person.3")
                                }
                            }
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
