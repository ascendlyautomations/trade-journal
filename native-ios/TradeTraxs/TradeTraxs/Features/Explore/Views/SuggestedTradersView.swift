import SwiftUI
import UIKit

/// Full suggested-traders list pushed from Explore (Feed stack).
struct SuggestedTradersView: View {
    @State private var viewModel: SuggestedTradersViewModel
    private let imagePipeline: any ImagePipeline

    @Environment(\.themeColors) private var colors

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: SuggestedTradersViewModel(
                explore: data.explore,
                search: data.search,
                profiles: data.profiles,
                session: data.session,
                detailCache: data.detailCache,
                navigationCoordinator: navigationCoordinator,
                messages: data.messages
            )
        )
        self.imagePipeline = data.imagePipeline
    }

    init(viewModel: SuggestedTradersViewModel, imagePipeline: any ImagePipeline) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
    }

    var body: some View {
        Group {
            if viewModel.isSearching {
                searchResultsContent
            } else {
                switch viewModel.phase {
                case .idle where viewModel.traders.isEmpty, .loading where viewModel.traders.isEmpty:
                    ProgressView("Loading traders…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("suggestedTraders.loading")
                case .failed(let message) where viewModel.traders.isEmpty:
                    ExperienceErrorState(
                        title: "Couldn't load suggested traders",
                        message: message,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                    .accessibilityIdentifier("suggestedTraders.error")
                case .loaded where viewModel.showsEmpty:
                    ExperienceEmptyState(
                        icon: .search,
                        title: "No suggested traders",
                        message: "Public profiles will appear here as the community grows."
                    )
                    .accessibilityIdentifier("suggestedTraders.empty")
                default:
                    listContent
                }
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Suggested Traders")
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search username or name"
        )
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.searchChanged()
        }
        .toolbar(.hidden, for: .tabBar)
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.loadIfNeeded()
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
        .accessibilityIdentifier("suggestedTraders.home")
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        if viewModel.searchPhase == .searching, viewModel.searchResults.isEmpty {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("suggestedTraders.search.loading")
        } else if case .failed(let message) = viewModel.searchPhase {
            ExperienceErrorState(
                title: "Search failed",
                message: message,
                onRetry: { viewModel.searchChanged() }
            )
            .accessibilityIdentifier("suggestedTraders.search.error")
        } else if viewModel.showsSearchEmpty {
            ExperienceEmptyState(
                icon: .search,
                title: "No matches",
                message: "Try another username or display name."
            )
            .accessibilityIdentifier("suggestedTraders.search.empty")
        } else {
            traderList(
                traders: viewModel.displayedTraders,
                showsPagination: false,
                accessibilityIdentifier: "suggestedTraders.search.results"
            )
        }
    }

    private var listContent: some View {
        traderList(
            traders: viewModel.displayedTraders,
            showsPagination: true,
            accessibilityIdentifier: "suggestedTraders.list"
        )
    }

    private func traderList(
        traders: [ExploreTraderSuggestion],
        showsPagination: Bool,
        accessibilityIdentifier: String
    ) -> some View {
        let _ = viewModel.followRevision
        return List {
            ForEach(traders) { trader in
                ExploreTraderListRow(
                    trader: trader,
                    profile: viewModel.resolvedProfile(for: trader),
                    imagePipeline: imagePipeline,
                    isFollowing: viewModel.isFollowing(trader),
                    showsFollowControl: viewModel.showsFollowControl(for: trader),
                    onOpen: { viewModel.openTrader(trader) },
                    onToggleFollow: { viewModel.toggleFollow(trader) }
                )
                .listRowBackground(colors.backgroundPrimary)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if viewModel.showsFollowControl(for: trader) {
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
                    if viewModel.showsFollowControl(for: trader) {
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
                .onAppear {
                    if showsPagination, trader.id == traders.last?.id {
                        viewModel.loadMoreIfNeeded()
                    }
                }
            }

            if showsPagination, viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("suggestedTraders.loadingMore")
            }

            if showsPagination, let message = viewModel.loadMoreFailedMessage {
                VStack(spacing: ExperienceSpacing.sm) {
                    Text(message)
                        .experienceStyle(.footnote, color: colors.secondaryText)
                        .multilineTextAlignment(.center)
                    Button("Try again") {
                        viewModel.retryLoadMore()
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, ExperienceSpacing.md)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("suggestedTraders.loadMoreError")
            }
        }
        .experiencePlainListStyle()
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
