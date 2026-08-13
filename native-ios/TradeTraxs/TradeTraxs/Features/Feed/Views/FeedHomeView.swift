import SwiftUI

/// Permanent Feed tab root — Instagram-style vertical Home Feed.
///
/// Data lifecycle is owned exclusively by ``FeedScreenViewModel``.
/// Child views (stories, cards, filters, empty/error) are render-only.
struct FeedHomeView: View {
    @State private var viewModel: FeedScreenViewModel
    private let imagePipeline: any ImagePipeline
    private let detailCache: DetailPresentationCache
    private let engagementStore: EngagementStore

    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator
    ) {
        _viewModel = State(
            initialValue: FeedScreenViewModel(
                feed: data.feed,
                trades: data.trades,
                profiles: data.profiles,
                achievements: data.achievements,
                session: data.session,
                detailCache: data.detailCache,
                engagementStore: data.engagementStore,
                navigationCoordinator: navigationCoordinator,
                realtimeHub: data.realtimeHub
            )
        )
        self.imagePipeline = data.imagePipeline
        self.detailCache = data.detailCache
        self.engagementStore = data.engagementStore
    }

    /// Tests / previews.
    init(
        viewModel: FeedScreenViewModel,
        imagePipeline: any ImagePipeline,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore
    ) {
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
        self.detailCache = detailCache
        self.engagementStore = engagementStore
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                if viewModel.entries.isEmpty {
                    FeedSkeleton()
                } else {
                    feedList
                }
            case .failed(let message):
                if viewModel.entries.isEmpty {
                    ExperienceErrorState(
                        title: "Couldn't load feed",
                        message: message,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                } else {
                    feedList
                }
            case .loaded where viewModel.showsEmpty:
                VStack(spacing: 0) {
                    if viewModel.scope == .following, !viewModel.stories.isEmpty {
                        storiesSection
                    }
                    ExperienceEmptyState(
                        icon: .feed,
                        title: emptyTitle,
                        message: emptyMessage
                    )
                }
            case .loaded:
                feedList
            }
        }
        .experienceScreenBackground()
        .experienceNavigationTitle("Feed")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                FeedScopeToggle(
                    scope: Binding(
                        get: { viewModel.scope },
                        set: { viewModel.setScope($0) }
                    )
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            contentFilterBar
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            viewModel.loadIfNeeded()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitesting-feed-text-only") {
                viewModel.setContentFilter(.posts)
            }
            #endif
        }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            // Private journal inserts do not belong in Feed. Public share goes through ContentMutationStore.
            guard TradeJournalMutationStore.shared.latestCreatedTrade?.visibility == .public else { return }
            Task { await viewModel.refresh() }
        }
        .onChange(of: ContentMutationStore.shared.revision) { _, _ in
            Task { await viewModel.refresh() }
        }
        .accessibilityIdentifier("feed.home")
    }

    private var contentFilterBar: some View {
        FeedContentToggle(
            filter: Binding(
                get: { viewModel.contentFilter },
                set: { viewModel.setContentFilter($0) }
            ),
            onChange: { _ in }
        )
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.backgroundPrimary.opacity(0.96))
        .accessibilityIdentifier("feed.header.contentFilter")
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.scope == .following, !viewModel.stories.isEmpty {
                    storiesSection
                    Rectangle()
                        .fill(colors.border.opacity(0.55))
                        .frame(height: ExperienceBorder.hairline)
                }

                ForEach(viewModel.visibleEntries) { entry in
                    FeedItemRow(
                        entry: entry,
                        author: viewModel.author(for: entry.authorProfileID),
                        imagePipeline: imagePipeline,
                        engagementStore: engagementStore,
                        onOpen: { viewModel.open(entry) },
                        onOpenAuthor: { viewModel.openAuthor(entry.authorProfileID) }
                    )
                    .onAppear {
                        Task { await viewModel.loadMoreIfNeeded(currentID: entry.id) }
                    }
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            )
                    )
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .padding(.vertical, ExperienceSpacing.md)
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: viewModel.visibleEntries.map(\.id))
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("feed.list")
    }

    private var storiesSection: some View {
        FeedStoriesRow(
            stories: viewModel.stories,
            detailCache: detailCache,
            imagePipeline: imagePipeline,
            onOpen: { viewModel.openStory($0) }
        )
    }

    private var emptyTitle: String {
        switch viewModel.contentFilter {
        case .all: return "Nothing here yet"
        case .trades: return "No trades yet"
        case .posts: return "No posts yet"
        case .clips: return "No clips yet"
        case .achievements: return "No achievements yet"
        }
    }

    private var emptyMessage: String {
        switch viewModel.scope {
        case .following:
            return "Follow traders to fill your Home Feed."
        case .global:
            return "New public activity will show up here."
        }
    }
}
