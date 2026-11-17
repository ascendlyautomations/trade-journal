import SwiftUI

/// Permanent Feed tab root — Instagram-style vertical Home Feed.
///
/// Data lifecycle is owned exclusively by ``FeedScreenViewModel``.
/// Child views (stories, cards, filters, empty/error) are render-only.
struct FeedHomeView: View {
    @Bindable private var feedScopeSession = FeedScopeSessionStore.shared
    @State private var viewModel: FeedScreenViewModel
    @State private var playbackCoordinator: FeedVideoPlaybackCoordinator
    @State private var scrollAnchor: FeedListScrollAnchor
    @State private var shareTarget: SharedContentShareTarget?
    private let imagePipeline: any ImagePipeline
    private let detailCache: DetailPresentationCache
    private let engagementStore: EngagementStore
    private let vaultStore: VaultStore

    @Environment(\.themeColors) private var colors
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.tabIsActive) private var tabIsActive
    @Environment(\.navigationEnvironment) private var navigationEnvironment
    @State private var scrollViewportFrame: CGRect = .zero
    @State private var feedImageWarmGeneration: UInt64 = 0
    @Bindable private var contextualTour = ContextualTourCoordinator.shared
    @State private var filterBarScrollCoordinator = FeedFilterBarScrollCoordinator()
    @State private var filterBarMeasuredHeight: CGFloat = 48

    init(
        data: DataEnvironment,
        navigationCoordinator: NavigationCoordinator,
        currentUserProfile: CurrentUserProfileStore? = nil,
        retainsTabPresentation: Bool = true
    ) {
        let presentation = FeedTabModelStore.presentation(
            retainsTabPresentation: retainsTabPresentation,
            makeViewModel: {
                FeedScreenViewModel(
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
            },
            makePlayback: {
                FeedVideoPlaybackCoordinator(storage: data.objectStorage)
            }
        )
        _playbackCoordinator = State(initialValue: presentation.1)
        _viewModel = State(initialValue: presentation.0)
        let anchor = FeedTabModelStore.listScrollAnchor(
            restoredOffset: presentation.0.retainedListScrollOffset
        )
        if let y = presentation.0.retainedListScrollOffset {
            anchor.applyRetainedOffset(y)
        }
        _scrollAnchor = State(initialValue: anchor)
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
        let anchor = FeedTabModelStore.listScrollAnchor(
            restoredOffset: viewModel.retainedListScrollOffset
        )
        if let y = viewModel.retainedListScrollOffset {
            anchor.applyRetainedOffset(y)
        }
        _scrollAnchor = State(initialValue: anchor)
        self.imagePipeline = imagePipeline
        self.detailCache = detailCache
        self.engagementStore = engagementStore
        self.vaultStore = vaultStore
    }

    var body: some View {
        feedHomeLifecycleDecorated
    }

    private var feedHomeLifecycleDecorated: some View {
        feedHomeChromeDecorated
        .onChange(of: feedTourChromeReady, initial: true) { _, ready in
            ContextualTourCoordinator.shared.setFeedChromeReady(ready)
        }
        .onChange(of: viewModel.phase) { _, _ in
            ContextualTourCoordinator.shared.setFeedChromeReady(feedTourChromeReady)
        }
        .onChange(of: navigationEnvironment.store.paths.feed) { _, _ in
            ContextualTourCoordinator.shared.setFeedChromeReady(feedTourChromeReady)
        }
        .task(id: tabIsActive) {
            guard tabIsActive else {
                preserveListScrollOffset()
                ContextualTourCoordinator.shared.setFeedChromeReady(false)
                syncFeedPlaybackSurfaceActive(reason: "tabChanged")
                ActiveScreenBootstrapPriorityGate.feed.setScreenActive(false)
                SocialRealtimeRepairSurfaces.shared.feedViewModel = nil
                viewModel.unsubscribeRealtime()
                SupabasePressureLog.screenRealtimeTransition(
                    screen: "feed",
                    active: false,
                    snapshot: appEnvironment.data.realtimeHub.realtimePressureSnapshot()
                )
                return
            }
            syncFeedPlaybackSurfaceActive(reason: "tabActive")
            ActiveScreenBootstrapPriorityGate.feed.setScreenActive(true)
            defer { ActiveScreenBootstrapPriorityGate.feed.setScreenActive(false) }
            MainThreadWorkProbe.measure("feed.tab.activate", surface: "feed") {
                SocialRealtimeRepairSurfaces.shared.feedViewModel = viewModel
                AuthenticatedLaunchPhasing.noteActiveTab(.feed)
                viewModel.loadIfNeeded()
                viewModel.noteTabBecameActive()
                viewModel.subscribeRealtime()
                SupabasePressureLog.screenRealtimeTransition(
                    screen: "feed",
                    active: true,
                    snapshot: appEnvironment.data.realtimeHub.realtimePressureSnapshot()
                )
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
            case .achievementDeleted(let achievementID):
                viewModel.applyAchievementRemoval(achievementID: achievementID)
            default:
                Task { await viewModel.refresh(trigger: .contentMutation) }
            }
        }
        .onChange(of: FollowMutationCoordinator.shared.revision) { _, _ in
            // Only user follow/unfollow edges affect Following timeline membership.
            guard viewModel.scope == .following else { return }
            switch FollowMutationCoordinator.shared.latest {
            case .followed, .unfollowed, .followRequestApproved:
                Task { await viewModel.reconcileFollowingAfterRelationshipChange() }
            default:
                break
            }
        }
        .onChange(of: navigationEnvironment.store.paths.feed.count) { oldCount, count in
            if count > 0 {
                preserveListScrollOffset()
            } else if oldCount > 0, count == 0 {
                restoreListScrollAfterDetailDismiss()
            }
            syncFeedPlaybackSurfaceActive(reason: "navigatedAway")
        }
        .onChange(of: viewModel.listScrollPresentationEpoch) { _, _ in
            scrollAnchor.resetToTop()
            filterBarScrollCoordinator.revealAtTop()
        }
        .onChange(of: viewModel.contentFilter, initial: true) { _, filter in
            filterBarScrollCoordinator.setTrackingEnabled(filter != .clips)
        }
        .onChange(of: contextualTour.pinsFeedFilterBar, initial: true) { _, pinned in
            filterBarScrollCoordinator.setWalkthroughPinned(pinned)
            if pinned {
                FeedFilterBarTourLayoutGate.resetForTourStep()
                guard viewModel.contentFilter != .clips else { return }
                scrollAnchor.resetToTop()
                filterBarScrollCoordinator.revealAtTop()
            } else {
                FeedFilterBarTourLayoutGate.clear()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .tradeTraxsLiveVoiceSessionDidChange)) { _ in
            if RoomLiveVoiceCoordinator.shared.isSessionActive {
                playbackCoordinator.pauseAll(reason: "liveVoiceActive")
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                playbackCoordinator.setSurfaceActive(false, reason: "appBackgrounded")
            } else {
                syncFeedPlaybackSurfaceActive(reason: "appForegrounded")
                if tabIsActive, viewModel.contentFilter == .clips {
                    playbackCoordinator.beginClipsExperience()
                }
            }
        }
        .onChange(of: viewModel.contentFilter) { oldFilter, newFilter in
            filterBarScrollCoordinator.setTrackingEnabled(newFilter != .clips)
            if newFilter != .clips {
                filterBarScrollCoordinator.revealAtTop()
            }
            if newFilter == .clips {
                playbackCoordinator.releaseAllPlayers()
                playbackCoordinator.beginClipsExperience()
            } else if oldFilter == .clips {
                playbackCoordinator.endClipsExperience()
            }
        }
        .onDisappear {
            preserveListScrollOffset()
            guard !tabIsActive else { return }
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

    private var feedHomeChromeDecorated: some View {
        feedPhaseContent
            .feedContentFilterSwipe(
                filter: viewModel.contentFilter,
                isEnabled: navigationEnvironment.store.paths.feed.isEmpty
            ) { viewModel.userSelectedContentFilter($0) }
            .experienceScreenBackground()
            .experienceFeedClipsChrome(isActive: viewModel.contentFilter == .clips)
            .experienceNavigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    FeedScopeToggle(
                        scope: Binding(
                            get: {
                                _ = feedScopeSession.revision
                                return viewModel.scope
                            },
                            set: { viewModel.setScope($0) }
                        )
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        navigationEnvironment.coordinator.open(.feed(.explore))
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .contextualTourTarget(.feedExplore)
                    }
                    .accessibilityLabel("Explore")
                    .accessibilityIdentifier("feed.explore")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        navigationEnvironment.coordinator.open(.feed(.rooms))
                    } label: {
                        Image(systemName: "person.3")
                            .contextualTourTarget(.feedTradeRooms)
                    }
                    .accessibilityLabel("Trade Rooms")
                    .accessibilityIdentifier("feed.rooms")
                }
            }
            .modifier(
                FeedClipsViewportLayoutModifier(
                    isClips: viewModel.contentFilter == .clips,
                    pinsFilterBarForTour: contextualTour.pinsFeedFilterBar,
                    coordinator: filterBarScrollCoordinator,
                    filterBarHeight: filterBarMeasuredHeight,
                    categoryBar: contentFilterBar
                )
            )
            .feedClipsBoundsLogging(isEnabled: viewModel.contentFilter == .clips)
            .modifier(FeedHomeRefreshModifier(isEnabled: viewModel.contentFilter != .clips) {
                await viewModel.refresh()
            })
    }

    @ViewBuilder
    private var feedPhaseContent: some View {
        switch viewModel.phase {
        case .idle, .loading:
            if viewModel.entries.isEmpty {
                FeedSkeleton(topClearance: filterBarMeasuredHeight)
            } else if viewModel.contentFilter == .clips {
                clipsExperience
            } else {
                feedList
            }
        case .failed(let message):
            if viewModel.entries.isEmpty {
                VStack(spacing: 0) {
                    feedTimelineScrollUnderFilterClearance
                    ExperienceErrorState(
                        title: "Couldn't load feed",
                        message: message,
                        onRetry: { Task { await viewModel.refresh() } }
                    )
                }
            } else if viewModel.contentFilter == .clips {
                clipsExperience
            } else {
                feedList
            }
        case .loaded where viewModel.isQueryReloadInProgress && viewModel.visibleEntries.isEmpty:
            if viewModel.contentFilter == .clips {
                clipsExperience
            } else {
                FeedSkeleton(topClearance: filterBarMeasuredHeight)
            }
        case .loaded where viewModel.showsEmpty:
            if viewModel.contentFilter == .clips {
                clipsEmptyState
            } else {
                VStack(spacing: 0) {
                    feedTimelineScrollUnderFilterClearance
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

    private var feedTimelineScrollUnderFilterClearance: some View {
        Color.clear
            .frame(height: filterBarMeasuredHeight)
            .accessibilityHidden(true)
    }

    /// Full filter header chrome (chips + padding + background) — transformed as one overlay unit.
    private var contentFilterBar: some View {
        feedContentFilterTourAnchor
            .padding(.horizontal, ExperienceSpacing.md)
            .padding(.top, ExperienceSpacing.sm)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.primaryBackground)
            .accessibilityIdentifier("feed.header.contentFilter")
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { _, height in
                guard height > 20 else { return }
                guard abs(filterBarMeasuredHeight - height) > 0.5 else { return }
                filterBarMeasuredHeight = height
            }
    }

    /// Tour anchor on the chip strip only — not the reserved auto-hide slot or padded chrome frame.
    private var feedContentFilterTourAnchor: some View {
        FeedContentToggle(
            filter: viewModel.contentFilter,
            onSelect: { viewModel.userSelectedContentFilter($0) }
        )
        .contextualTourTarget(.feedContentFilters)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { _, frame in
            guard contextualTour.pinsFeedFilterBar, frame.height > 1, frame.width > 1 else { return }
            FeedFilterBarTourLayoutGate.markLaidOut()
#if DEBUG
            ContextualTourDebug.log("feedFilters chip global=\(frame) mayMeasure=\(FeedFilterBarTourLayoutGate.mayMeasure)")
#endif
        }
    }

    private var feedList: some View {
        ScrollView {
            VStack(spacing: 0) {
                feedTimelineScrollUnderFilterClearance
                if viewModel.scope == .following {
                    storiesSection
                    FeedSectionSeparator()
                }

                LazyVStack(spacing: 0) {
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
                            onOpenComments: { openFeedEntryComments(entry) },
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
                            #if DEBUG
                            FeedScrollRowLifecycleDiagnostics.logRowAppear(
                                entryID: entry.id,
                                restoredFromSessionCache: FeedDisplayImageSessionCache.uiImage(forEntryID: entry.id) != nil
                            )
                            #endif
                            Task { await viewModel.loadMoreIfNeeded(currentID: entry.id) }
                            guard shouldPrefetchFeedImagesWhenRowAppears(entryID: entry.id) else { return }
                            FeedImagePrefetch.prefetchNearby(
                                entries: viewModel.visibleEntries,
                                currentEntryID: entry.id,
                                pipeline: imagePipeline
                            )
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .padding(.vertical, ExperienceSpacing.md)
                    }
                }
            }
            .environment(\.feedScrollViewportFrame, scrollViewportFrame)
            .experienceDisablesSystemScrollToTop()
        }
        .id(FeedListScrollSurfaceIdentity.feedTimeline)
        .scrollPosition(scrollAnchor.binding)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, contentOffsetY in
            guard navigationEnvironment.store.paths.feed.isEmpty, tabIsActive else { return }
            scrollAnchor.noteMeasuredContentOffset(contentOffsetY)
            guard viewModel.contentFilter != .clips else { return }
            filterBarScrollCoordinator.processContentOffset(contentOffsetY)
        }
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame in
            guard !framesApproximatelyEqual(scrollViewportFrame, frame) else { return }
            scrollViewportFrame = frame
        }
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("feed.list")
        .onAppear {
            scheduleFeedImageCacheWarmAndViewportGate()
        }
        .onChange(of: viewModel.visibleEntryIDs) { _, _ in
            scheduleFeedImageCacheWarmAndViewportGate()
        }
    }

    /// Prefetch runs only near the list tail — upward scroll remounts must not restart utility prefetch work.
    private func shouldPrefetchFeedImagesWhenRowAppears(entryID: String) -> Bool {
        guard let index = viewModel.visibleEntries.firstIndex(where: { $0.id == entryID }) else {
            return false
        }
        let tailWindow = max(0, viewModel.visibleEntries.count - 6)
        return index >= tailWindow
    }

    private func scheduleFeedImageCacheWarmAndViewportGate() {
        FeedImageViewportReadiness.registerInitialViewport(entries: viewModel.visibleEntries)
        feedImageWarmGeneration &+= 1
        let generation = feedImageWarmGeneration
        let entries = viewModel.visibleEntries
        Task(priority: .userInitiated) {
            guard generation == feedImageWarmGeneration else { return }
            await FeedImageCacheWarmer.warmInitialViewport(
                entries: entries,
                pipeline: imagePipeline
            )
        }
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
            },
            preservedActiveClipEntryID: viewModel.retainedClipsActiveEntryID,
            onActiveClipEntryIDChange: { viewModel.rememberClipsActiveEntryID($0) },
            listScrollPresentationEpoch: viewModel.listScrollPresentationEpoch
        )
        .id(FeedListScrollSurfaceIdentity.feedClipsPager)
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
        preserveListScrollOffset()
        if case .clip = entry {
            viewModel.rememberClipsActiveEntryID(entry.id)
            playbackCoordinator.releaseAllPlayers()
        }
        viewModel.open(entry)
    }

    private func openFeedEntryComments(_ entry: FeedTimelineEntry) {
        preserveListScrollOffset()
        viewModel.openComments(entry)
    }

    private func preserveListScrollOffset() {
        viewModel.rememberListScrollOffset(scrollAnchor.offset)
    }

    private func restoreListScrollAfterDetailDismiss() {
        guard viewModel.contentFilter != .clips else { return }
        guard let offset = viewModel.retainedListScrollOffset, offset > 0.5 else { return }
        scrollAnchor.applyRetainedOffset(offset)
        scrollAnchor.scheduleLayoutStableRestore()
    }

    /// Pinned filter chrome is measurable once the feed root has left its initial idle bootstrap.
    private var feedTourChromeReady: Bool {
        guard tabIsActive, navigationEnvironment.store.paths.feed.isEmpty else { return false }
        switch viewModel.phase {
        case .idle:
            return false
        case .loading, .loaded, .failed:
            return true
        }
    }

    private var isFeedPlaybackSurfaceActive: Bool {
        tabIsActive && navigationEnvironment.store.paths.feed.isEmpty
    }

    private func syncFeedPlaybackSurfaceActive(reason: String) {
        playbackCoordinator.setSurfaceActive(isFeedPlaybackSurfaceActive, reason: reason)
    }

    private func reportAction(for entry: FeedTimelineEntry) -> (() -> Void)? {
        guard let request = entry.reportRequest(viewerID: viewModel.viewerID) else { return nil }
        return {
            ExperienceHaptics.play(.selection)
            appEnvironment.contentReportPresenter.present(request)
        }
    }

    private func framesApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5
            && abs(lhs.origin.y - rhs.origin.y) < 0.5
            && abs(lhs.size.width - rhs.size.width) < 0.5
            && abs(lhs.size.height - rhs.size.height) < 0.5
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

/// Stable identity for feed scroll surfaces — only changes when the user resets filter/scope scroll.
private enum FeedListScrollSurfaceIdentity {
    static let feedTimeline = "feed.scroll.timeline"
    static let feedClipsPager = "feed.scroll.clips"
}

/// Clips: filter bar in a fixed stack above the pager (tour layout anchor).
/// Timeline: constant top inset on feed content + floating filter bar overlay (offset/opacity only).
private struct FeedClipsViewportLayoutModifier<CategoryBar: View>: ViewModifier {
    let isClips: Bool
    let pinsFilterBarForTour: Bool
    let coordinator: FeedFilterBarScrollCoordinator
    let filterBarHeight: CGFloat
    let categoryBar: CategoryBar

    func body(content: Content) -> some View {
        if isClips {
            VStack(spacing: 0) {
                categoryBar.feedClipsBoundsAnchor(.categoryBar)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                    .feedClipsBoundsAnchor(.pager)
            }
        } else {
            content.modifier(
                FeedTimelineFilterBarOverlayModifier(
                    coordinator: coordinator,
                    pinsFilterBarForTour: pinsFilterBarForTour,
                    filterBarHeight: filterBarHeight,
                    categoryBar: categoryBar
                )
            )
        }
    }
}

/// Timeline filter header — overlay below nav; feed layout never changes when visibility toggles.
private struct FeedTimelineFilterBarOverlayModifier<CategoryBar: View>: ViewModifier {
    @Bindable var coordinator: FeedFilterBarScrollCoordinator
    let pinsFilterBarForTour: Bool
    let filterBarHeight: CGFloat
    let categoryBar: CategoryBar

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isBarPresented: Bool {
        pinsFilterBarForTour || coordinator.isEffectivelyVisible
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                FeedTimelineFilterBarChrome(
                    isBarPresented: isBarPresented,
                    filterBarHeight: filterBarHeight,
                    reduceMotion: reduceMotion,
                    bar: categoryBar
                )
            }
    }
}

/// Single transform target for chips, padding, background, and measured chrome.
private struct FeedTimelineFilterBarChrome<Bar: View>: View {
    let isBarPresented: Bool
    let filterBarHeight: CGFloat
    let reduceMotion: Bool
    let bar: Bar

    var body: some View {
        bar
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: filterBarHeight, alignment: .top)
            .clipped()
            .offset(y: isBarPresented ? 0 : -filterBarHeight)
            .opacity(isBarPresented ? 1 : 0)
            .allowsHitTesting(isBarPresented)
            .accessibilityHidden(!isBarPresented)
            .animation(
                ExperienceMotion.preferred(ExperienceMotion.selection, reduceMotion: reduceMotion),
                value: isBarPresented
            )
    }
}
