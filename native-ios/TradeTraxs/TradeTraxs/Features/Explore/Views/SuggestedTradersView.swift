import SwiftUI
import UIKit

/// Full suggested-traders list pushed from Explore (Feed stack).
struct SuggestedTradersView: View {
    @State private var viewModel: SuggestedTradersViewModel
    @FocusState private var isSearchFocused: Bool

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
            if case .failed(let message) = viewModel.phase,
               viewModel.traders.isEmpty,
               !viewModel.isSearching
            {
                ExperienceErrorState(
                    title: "Couldn't load suggested traders",
                    message: message,
                    onRetry: { Task { await viewModel.refresh() } }
                )
                .accessibilityIdentifier("suggestedTraders.error")
            } else if showsBootstrapLoading {
                ProgressView("Loading traders…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("suggestedTraders.loading")
            } else {
                primaryList
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Suggested Traders")
        .toolbar(.hidden, for: .tabBar)
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.loadIfNeeded()
        }
        .experienceFormFocusSync($isSearchFocused)
        .accessibilityIdentifier("suggestedTraders.home")
    }

    private var showsBootstrapLoading: Bool {
        switch viewModel.phase {
        case .idle, .loading:
            return viewModel.traders.isEmpty && !viewModel.isSearching
        default:
            return false
        }
    }

    private var primaryList: some View {
        let _ = viewModel.followRevision
        let showsPagination = !viewModel.isSearching
        return List {
            filterHeader
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())

            if viewModel.showsEmpty {
                listEmptyRow(
                    title: "No suggested traders",
                    message: "Public profiles will appear here as the community grows.",
                    identifier: "suggestedTraders.empty"
                )
            } else if viewModel.isSearching, viewModel.searchPhase == .searching,
                      viewModel.displayedTraders.isEmpty
            {
                HStack {
                    Spacer()
                    ProgressView("Searching…")
                    Spacer()
                }
                .padding(.vertical, ExperienceSpacing.lg)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("suggestedTraders.search.loading")
            } else if case .failed(let message) = viewModel.searchPhase, viewModel.isSearching {
                ExperienceErrorState(
                    title: "Search failed",
                    message: message,
                    onRetry: { viewModel.searchChanged() }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("suggestedTraders.search.error")
            } else if viewModel.showsFilteredEmpty {
                listEmptyRow(
                    title: "No matching traders",
                    message: viewModel.isSearching
                        ? "Try another username, display name, or category."
                        : "No traders match this category yet.",
                    identifier: "suggestedTraders.filter.empty"
                )
            } else {
                ForEach(viewModel.displayedTraders) { trader in
                    traderRow(trader, showsPagination: showsPagination)
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
        }
        .scrollDismissesKeyboard(.never)
        .experiencePlainListStyle()
        .accessibilityIdentifier(
            viewModel.isSearching ? "suggestedTraders.search.results" : "suggestedTraders.list"
        )
    }

    private func listEmptyRow(title: String, message: String, identifier: String) -> some View {
        ExperienceCompactEmptyState(
            icon: .search,
            title: title,
            message: message,
            accessibilityIdentifier: identifier
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(
            top: ExperienceSpacing.sm,
            leading: ExperienceSpacing.md,
            bottom: ExperienceSpacing.md,
            trailing: ExperienceSpacing.md
        ))
    }

    private var filterHeader: some View {
        VStack(alignment: .leading, spacing: ExperienceSpacing.sm) {
            ExperienceSearchField(
                text: $viewModel.searchText,
                placeholder: "Search traders...",
                accessibilityIdentifier: "suggestedTraders.search",
                cornerRadius: ExperienceRadius.sm,
                showsSearchIcon: false,
                showsClearButton: false,
                showsTrailingCancelWhenActive: true,
                isFocused: $isSearchFocused,
                onCancel: cancelSearch
            )
            .padding(.horizontal, ExperienceSpacing.md)
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.searchChanged()
            }

            SuggestedTraderCategoryFilterBar(
                selected: viewModel.categoryTab,
                onSelect: { viewModel.selectCategoryTab($0) }
            )
            .padding(.horizontal, ExperienceSpacing.md)
        }
        .padding(.vertical, ExperienceSpacing.sm)
    }

    private func cancelSearch() {
        viewModel.searchText = ""
        viewModel.searchChanged()
        isSearchFocused = false
        ExperienceKeyboard.dismissFormKeyboard()
    }

    private func traderRow(_ trader: ExploreTraderSuggestion, showsPagination: Bool) -> some View {
        let traders = viewModel.displayedTraders
        return ExploreTraderListRow(
            trader: trader,
            profile: viewModel.resolvedProfile(for: trader),
            viewerProfileID: viewModel.authenticatedProfileID,
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
                _ = ExperienceClipboard.copy("@\(trader.profile.username)")
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
}