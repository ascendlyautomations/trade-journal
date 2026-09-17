import SwiftUI

/// Permanent Feed tab root — Instagram-style vertical Home Feed.
///
/// Data lifecycle is owned exclusively by ``FeedScreenViewModel``.
/// Child views (stories, cards, filters, empty/error) are render-only.
struct FeedHomeView: View {
    @State private var viewModel: FeedScreenViewModel
    @State private var playbackCoordinator: FeedVideoPlaybackCoordinator
    @State private var shareTarget: SharedContentShareTarget?
    private let imagePipeline: any ImagePipeline
    private let detailCache: DetailPresentationCache
    private let engagementStore: EngagementStore
    private let vaultStore: VaultStore

    @Environment(\.themeColors) private var colors
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tabIsActive) private var tabIsActive
    @State private var scrollViewportFrame: CGRect = .zero

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        currentUserProfile: CurrentUserProfileStore? = nil
    ) {
        _playbackCoordinator = State(
            initialValue: FeedVideoPlaybackCoordinator(storage: data.objectStorage)
        )
        _viewModel = State(
            initialValue: FeedScreenViewModel(
                feed: data.feed,
                trades: data.trades,
                profiles: data.profiles,
                achievements: data.achievements,
                session: data.session,
                detailCache: data.detailCache,
                engagementStore: data.engagementStore,
                vaultStore: data.vaultStore,
                navigationCoordinator: navigationCoordinator,
                realtimeHub: data.realtimeHub,
                rpc: data.rpc,
                messages: data.messages,
                currentUserProfile: currentUserProfile
            )
        )
        self.imagePipeline = data.imagePipeline
        self.detailCache = data.detailCache
        self.engagementStore = data.engagementStore
        self.vaultStore = data.vaultStore
    }

    /// Tests / previews.
    init(
        viewModel: FeedScreenViewModel,
        imagePipeline: any ImagePipeline,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore,
        vaultStore: VaultStore,
        playbackCoordinator: FeedVideoPlaybackCoordinator
    ) {
        _playbackCoordinator = State(initialValue: playbackCoordinator)
        _viewModel = State(initialValue: viewModel)
        self.imagePipeline = imagePipeline
        self.detailCache = detailCache
        self.engagementStore = engagementStore
        self.vaultStore = vaultStore
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                if viewModel.entries.isEmpty {
                    FeedSkeleton()
                } else if viewModel.contentFilter == .clips {
                    clipsExperience
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
                } else if viewModel.contentFilter == .clips {
                    clipsExperience
                } else {
                    feedList
                }
            case .loaded where viewModel.isQueryReloadInProgress && viewModel.visibleEntries.isEmpty:
                if viewModel.contentFilter == .clips {
                    clipsExperience
                } else {
                    FeedSkeleton()
                }
            case .loaded where viewModel.showsEmpty:
                if viewModel.contentFilter == .clips {
                    clipsEmptyState
                } else {
                    VStack(spacing: 0) {
                        if viewModel.scope == .following {
                            storiesSection
                        }
                        ExperienceEmptyState(
                            icon: .feed,
                            title: emptyTitle,
                            message: emptyMessage
                        )
                    }
                }
            case .loaded:
                if viewModel.contentFilter == .clips {
                    clipsExperience
                } else {
                    feedList
                }
            }
        }
        .experienceScreenBackground()
        .experienceFeedClipsChrome(isActive: viewModel.contentFilter == .clips)
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
        .modifier(
            FeedClipsViewportLayoutModifier(
                isClips: viewModel.contentFilter == .clips,
                categoryBar: contentFilterBar
            )
        )
        .feedClipsBoundsLogging(isEnabled: viewModel.contentFilter == .clips)
        .modifier(FeedHomeRefreshModifier(isEnabled: viewModel.contentFilter != .clips) {
            await viewModel.refresh()
        })
        .task(id: tabIsActive) {
            guard tabIsActive else {
                viewModel.unsubscribeRealtime()
                return
            }
            MainThreadWorkProbe.measure("feed.tab.activate", surface: "feed") {
                viewModel.loadIfNeeded()
                viewModel.subscribeRealtime()
            }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitesting-feed-text-only") {
                viewModel.userSelectedContentFilter(.posts)
            }
            #endif
        }
        .onChange(of: TradeJournalMutationStore.shared.revision) { _, _ in
            switch TradeJournalMutationStore.shared.latest {
            case .created(let trade), .updated(let trade):
                viewModel.applyJournalPublicTrade(trade)
            case .deleted(let id, _):
                viewModel.applyJournalPublicTradeRemoval(tradeID: id)
            case .bulkImport:
                Task { await viewModel.refresh(trigger: .journalMutation) }
            default:
                break
            }
        }
        .onChange(of: ContentMutationStore.shared.revision) { _, _ in
            switch ContentMutationStore.shared.latest {
            case .story(let story):
                viewModel.applyStoryCreated(story)
            case .storyDeleted(let storyID):
                viewModel.applyStoryDeleted(storyID)
            case .postDeleted(let postID):
                viewModel.applyPostRemoval(postID: postID)
            case .reelDeleted(let reelID):
                viewModel.applyReelRemoval(reelID: reelID)
            default:
                Task { await viewModel.refresh(trigger: .contentMutation) }
            }
        }
        .onChange(of: FollowMutationCoordinator.shared.revision) { _, _ in
            // Only user follow/unfollow edges affect Following timeline membership.
            guard viewModel.scope == .following else { return }
            switch FollowMutationCoordinator.shared.latest {
            case .followed, .unfollowed, .followRequestApproved:
                Task { await viewModel.refresh(trigger: .followingChanged) }
            default:
                break
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                playbackCoordinator.releaseAllPlayers()
            } else if viewModel.contentFilter == .clips {
                playbackCoordinator.beginClipsExperience()
            }
        }
        .onChange(of: viewModel.contentFilter) { oldFilter, newFilter in
            if newFilter == .clips {
                playbackCoordinator.releaseAllPlayers()
                playbackCoordinator.beginClipsExperience()
            } else if oldFilter == .clips {
                playbackCoordinator.endClipsExperience()
            }
        }
        .onDisappear {
            playbackCoordinator.releaseAllPlayers()
        }
        .sheet(item: $shareTarget) { target in
            SharedContentShareSheet(
                target: target,
                data: appEnvironment.data,
                onClose: { shareTarget = nil }
            )
        }
        .accessibilityIdentifier("feed.home")
    }

    private var contentFilterBar: some View {
        FeedContentToggle(
            filter: viewModel.contentFilter,
            onSelect: { viewModel.userSelectedContentFilter($0) }
        )
        .padding(.horizontal, ExperienceSpacing.md)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            colors.backgroundPrimary
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("feed.header.contentFilter")
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.scope == .following {
                    storiesSection
                    FeedSectionSeparator()
                }

                ForEach(viewModel.visibleEntries) { entry in
                    FeedItemRow(
                        entry: entry,
                        author: viewModel.author(for: entry.authorProfileID),
                        imagePipeline: imagePipeline,
                        engagementStore: engagementStore,
                        vaultStore: vaultStore,
                        detailCache: detailCache,
                        playbackCoordinator: playbackCoordinator,
                        onOpen: { openFeedEntry(entry) },
                        onOpenAuthor: { viewModel.openAuthor(entry.authorProfileID) },
                        onOpenLinkedTrade: { viewModel.openLinkedTrade($0) },
                        onOpenLinkedClip: { reelID in
                            playbackCoordinator.releaseAllPlayers()
                            viewModel.openLinkedClip(reelID)
                        },
                        viewerID: viewModel.viewerID,
                        onReport: reportAction(for: entry),
                        onShare: {
                            shareTarget = SharedContentShareTarget.from(
                                entry: entry,
                                author: viewModel.author(for: entry.authorProfileID)
                            )
                        }
                    )
                    .onAppear {
                        Task { await viewModel.loadMoreIfNeeded(currentID: entry.id) }
                        FeedImagePrefetch.prefetchNearby(
                            entries: viewModel.visibleEntries,
                            currentEntryID: entry.id,
                            pipeline: imagePipeline
                        )
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
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: viewModel.visibleEntryIDs)
            .environment(\.feedScrollViewportFrame, scrollViewportFrame)
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            scrollViewportFrame = frame
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("feed.list")
    }

    private var clipsExperience: some View {
        FeedClipsPagerView(
            entries: viewModel.visibleEntries,
            author: { viewModel.author(for: $0) },
            imagePipeline: imagePipeline,
            detailCache: detailCache,
            engagementStore: engagementStore,
            vaultStore: vaultStore,
            playbackCoordinator: playbackCoordinator,
            isLoadingMore: viewModel.isLoadingMore,
            viewerID: viewModel.viewerID,
            onOpenAuthor: { viewModel.openAuthor($0) },
            onOpenLinkedTrade: { viewModel.openLinkedTrade($0) },
            onReport: { entry in reportAction(for: entry) },
            onShare: { entry in
                shareTarget = SharedContentShareTarget.from(
                    entry: entry,
                    author: viewModel.author(for: entry.authorProfileID)
                )
            },
            onOpenDetail: { openFeedEntry($0) },
            onLoadMore: { entryID in
                Task { await viewModel.loadMoreIfNeeded(currentID: entryID) }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.primaryBackground)
    }

    private var clipsEmptyState: some View {
        ExperienceEmptyState(
            icon: .video,
            title: emptyTitle,
            message: emptyMessage
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var storiesSection: some View {
        FeedStoriesRow(
            stories: viewModel.stories,
            viewerID: viewModel.viewerID,
            detailCache: detailCache,
            imagePipeline: imagePipeline,
            onAddStory: { viewModel.openCreateStory() },
            onOpen: { viewModel.openStory($0) }
        )
    }

    private var emptyTitle: String {
        switch viewModel.contentFilter {
        case .all: return "Your feed is quiet"
        case .trades: return "No trades yet"
        case .posts: return "No posts yet"
        case .clips: return "No clips yet"
        case .achievements: return "No achievements yet"
        }
    }

    private var emptyMessage: String {
        switch viewModel.scope {
        case .following:
            return "Follow traders to see their activity here."
        case .global:
            return "New public activity will show up here."
        }
    }

    private func openFeedEntry(_ entry: FeedTimelineEntry) {
        if case .clip = entry {
            playbackCoordinator.releaseAllPlayers()
        }
        viewModel.open(entry)
    }

    private func reportAction(for entry: FeedTimelineEntry) -> (() -> Void)? {
        guard let request = entry.reportRequest(viewerID: viewModel.viewerID) else { return nil }
        return {
            ExperienceHaptics.play(.selection)
            appEnvironment.contentReportPresenter.present(request)
        }
    }
}

/// Pull-to-refresh only for non-Clips feed modes — nested Clips pager owns its own scroll surface.
private struct FeedHomeRefreshModifier: ViewModifier {
    let isEnabled: Bool
    let action: () async -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.refreshable {
                await action()
            }
        } else {
            content
        }
    }
}

/// Clips mode uses a structural VStack so the pager starts exactly below the category bar.
/// Other feed modes keep the floating top inset layout.
private struct FeedClipsViewportLayoutModifier<CategoryBar: View>: ViewModifier {
    let isClips: Bool
    let categoryBar: CategoryBar

    func body(content: Content) -> some View {
        if isClips {
            VStack(spacing: 0) {
                categoryBar
                    .feedClipsBoundsAnchor(.categoryBar)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                    .feedClipsBoundsAnchor(.pager)
            }
        } else {
            content
                .safeAreaInset(edge: .top, spacing: 0) {
                    categoryBar
                }
        }
    }
}
