import Foundation
import Observation

/// Canonical Profile screen owner — one bootstrap, one ``ProfileState``, render-only children.
///
/// Reference architecture for every TradeTraxs screen:
/// Screen ViewModel → coordinated bootstrap → shared state → section VMs apply / paginate only.
@Observable
@MainActor
final class ProfileScreenViewModel {
    private(set) var state = ProfileState()
    let contentStore: ProfileContentStore
    let headerViewModel: ProfileHeaderViewModel
    private(set) var shellViewModel: ProfileShellViewModel?

    private let data: DataEnvironment
    private let navigationCoordinator: NavigationCoordinator
    private let showsOwnerChrome: Bool
    private let target: ProfileContentStore.Target

    private var bootstrapTask: Task<Void, Never>?

    init(
        target: ProfileContentStore.Target,
        currentUserProfile _: CurrentUserProfileStore,
        navigationCoordinator: NavigationCoordinator,
        authenticationCoordinator _: AuthenticationCoordinator?,
        data: DataEnvironment,
        showsOwnerChrome: Bool
    ) {
        self.target = target
        self.data = data
        self.navigationCoordinator = navigationCoordinator
        self.showsOwnerChrome = showsOwnerChrome

        let content = ProfileContentStore(
            target: target,
            profiles: data.profiles,
            rooms: data.rooms,
            session: data.session,
            imagePipeline: data.imagePipeline,
            detailCache: data.detailCache
        )
        contentStore = content
        headerViewModel = ProfileHeaderViewModel(
            store: content,
            messages: data.messages,
            session: data.session,
            navigationCoordinator: navigationCoordinator,
            detailCache: data.detailCache
        )
    }

    var showsSettingsToolbar: Bool {
        showsOwnerChrome && contentStore.isOwner
    }

    /// Exactly one bootstrap on first presentation (unless already completed).
    func onAppear(currentUserProfile: CurrentUserProfileStore) {
        seedOwnerCacheIfNeeded(from: currentUserProfile)
        FollowMutationCoordinator.shared.registerActiveProfile(screen: self)
        if case .currentUser = target {
            OwnerProfileOptimisticStore.shared.registerOwnerScreen(self)
        }
        if state.didBootstrap {
            syncSectionSnapshotsIntoState()
            reapplyOptimisticOverlaysToSections()
            return
        }
        bootstrapIfNeeded(force: false)
    }

    /// FollowMutationCoordinator — keep ProfileState aligned with shared caches.
    func applyExternalFollowState(isFollowing: Bool, stats: ProfileStats?) {
        var next = state
        if !next.isOwner {
            next.isFollowing = isFollowing
        }
        if let stats {
            next.stats = stats
        }
        guard next != state else { return }
        applyLocalState(next)
    }

    /// Standard lifecycle — first coordinated bootstrap (no-op when already done).
    func bootstrapIfNeeded() async {
        await performBootstrap(force: false)
    }

    /// Pull-to-refresh — explicit full-screen re-bootstrap.
    func refresh() async {
        ExperienceHaptics.play(.selection)
        state.isRefreshing = true
        await performBootstrap(force: true)
        state.isRefreshing = false
    }

    /// Profile pagination lives on section VMs after bootstrap; screen-level no-op.
    func loadMore() async {}

    /// Profile has no screen-owned realtime loop today.
    func subscribeRealtime() {}

    func unsubscribeRealtime() {}

    /// Header retry button — same as pull-to-refresh.
    func retryBootstrap() {
        bootstrapIfNeeded(force: true)
    }

    func syncShellIfNeeded() {
        guard let profileID = state.profileID ?? contentStore.resolvedProfileID else {
            shellViewModel = nil
            return
        }
        if shellViewModel?.profileID != profileID {
            shellViewModel = ProfileShellViewModel(
                profileID: profileID,
                data: data,
                navigationCoordinator: navigationCoordinator,
                isOwner: state.isOwner || contentStore.isOwner
            )
        }
        shellViewModel?.apply(state: state)
    }

    func reconcileOwnershipIfNeeded() {
        guard let id = state.profileID ?? contentStore.resolvedProfileID,
              shellViewModel?.profileID == id,
              shellViewModel?.isOwner != contentStore.isOwner
        else { return }
        shellViewModel = ProfileShellViewModel(
            profileID: id,
            data: data,
            navigationCoordinator: navigationCoordinator,
            isOwner: contentStore.isOwner
        )
        shellViewModel?.apply(state: state)
        activateShellForLaunch()
    }

    func activateShellForLaunch() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uitesting-profile-stats") {
            shellViewModel?.select(.stats)
            return
        }
        if args.contains("-uitesting-profile-posts") {
            shellViewModel?.select(.posts)
            return
        }
        #endif
        shellViewModel?.activateSelected()
    }

    func openSettings() {
        headerViewModel.openSettings()
    }

    // MARK: - Optimistic owner mutations (no network)

    /// Called by ``OwnerProfileOptimisticStore`` when the owner Profile screen is registered.
    func absorbOwnerOptimisticOverlays() {
        guard isOwnerTarget else { return }
        let merged = OwnerProfileOptimisticStore.shared.merging(into: state)
        guard merged != state else { return }
        let skipPosts = shellViewModel?.posts?.hasAuthoritativePayload == true
        applyLocalState(merged, skipPostsBootstrap: skipPosts)
        if skipPosts, let visible = shellViewModel?.posts?.items {
            syncPostsFromSection(visible)
        }
    }

    func applyOptimisticPost(_ post: Post) {
        guard isOwnerTarget else { return }
        guard matchesOwner(post.authorProfileID) else { return }
        data.detailCache.seed(post)

        syncShellIfNeeded()
        shellViewModel?.ensurePostsSection()

        let basePosts = preferredPostsBase()
        var next = state
        next.posts = OwnerProfileOptimisticStore.upserting(post, into: basePosts)

        shellViewModel?.posts?.notePublishSucceeded(
            post,
            preservingExisting: basePosts
        )

        if next.phase == .idle || next.phase == .loading {
            applyLocalState(next, skipPostsBootstrap: true)
        } else {
            next.phase = .loaded
            next.didBootstrap = true
            applyLocalState(next, skipPostsBootstrap: true)
        }

        if let visible = shellViewModel?.posts?.items {
            syncPostsFromSection(visible)
        }
    }

    /// Keeps ``ProfileState.posts`` aligned with the section VM after authoritative refresh.
    func syncPostsFromSection(_ posts: [Post]) {
        guard isOwnerTarget else { return }
        guard state.posts != posts else { return }
        var next = state
        next.posts = posts
        next.lastUpdated = Date()
        state = next
    }

    private func preferredPostsBase() -> [Post] {
        if let postsVM = shellViewModel?.posts, !postsVM.items.isEmpty {
            return postsVM.items
        }
        if !state.posts.isEmpty {
            return state.posts
        }
        return OwnerProfileOptimisticStore.shared.posts.filter {
            matchesOwner($0.authorProfileID)
        }
    }

    private func syncSectionSnapshotsIntoState() {
        guard let postsVM = shellViewModel?.posts, postsVM.hasAuthoritativePayload else { return }
        guard state.posts != postsVM.items else { return }
        var next = state
        next.posts = postsVM.items
        state = next
    }

    /// Re-merge owner overlays when returning to Profile without a full bootstrap republish.
    private func reapplyOptimisticOverlaysToSections() {
        guard isOwnerTarget else { return }
        var next = OwnerProfileOptimisticStore.shared.merging(into: state)
        guard next != state else {
            shellViewModel?.apply(state: state)
            return
        }
        next.lastUpdated = Date()
        next.isRefreshing = state.isRefreshing
        state = next
        shellViewModel?.apply(state: next)
    }

    func applyOptimisticReel(_ reel: Reel) {
        guard isOwnerTarget else { return }
        guard matchesOwner(reel.authorProfileID) else { return }
        guard OwnerProfileOptimisticStore.isListedOnOwnerProfile(reel) else { return }
        data.detailCache.seed(reel)
        var next = state
        let baseClips: [Reel]
        if let clipsVM = shellViewModel?.clips, clipsVM.hasAuthoritativePayload {
            baseClips = clipsVM.items
        } else {
            baseClips = next.clips
        }
        next.clips = OwnerProfileOptimisticStore.upserting(reel, into: baseClips)
        if next.phase == .idle || next.phase == .loading {
            applyLocalState(next)
            return
        }
        next.phase = .loaded
        next.didBootstrap = true
        applyLocalState(next)
    }

    func applyOptimisticAchievement(_ achievement: Achievement) {
        guard isOwnerTarget else { return }
        guard matchesOwner(achievement.ownerProfileID) else { return }
        data.detailCache.seed(achievement)
        var next = state
        let baseAchievements: [Achievement]
        if let achievementsVM = shellViewModel?.achievements, achievementsVM.hasAuthoritativePayload {
            baseAchievements = achievementsVM.items
        } else {
            baseAchievements = next.achievements
        }
        next.achievements = OwnerProfileOptimisticStore.upserting(achievement, into: baseAchievements)
        if var stats = next.stats {
            stats.payoutTotal = Self.publicPayoutTotal(from: next.achievements)
            next.stats = stats
            data.detailCache.seed(stats: stats)
        }
        if next.phase == .idle || next.phase == .loading {
            applyLocalState(next)
            return
        }
        next.phase = .loaded
        next.didBootstrap = true
        applyLocalState(next)
    }

    private static func publicPayoutTotal(from achievements: [Achievement]) -> Decimal {
        ProfilePayoutTotals.sum(from: achievements.filter(\.isPublic))
    }

    func applyOptimisticPostRemoval(id: PostID) {
        guard isOwnerTarget else { return }
        data.detailCache.removePost(id: id)
        var next = state
        next.posts.removeAll { $0.id == id }
        applyLocalState(next)
    }

    func applyOptimisticReelRemoval(id: ReelID) {
        guard isOwnerTarget else { return }
        data.detailCache.removeReel(id: id)
        var next = state
        next.clips.removeAll { $0.id == id }
        applyLocalState(next)
    }

    // MARK: - Bootstrap

    private var isOwnerTarget: Bool {
        if case .currentUser = target { return true }
        return state.isOwner
    }

    private func matchesOwner(_ authorID: ProfileID) -> Bool {
        if let profileID = state.profileID ?? contentStore.resolvedProfileID {
            return authorID == profileID
        }
        // Pre-bootstrap owner tab — accept creates for the session user once known.
        return isOwnerTarget
    }

    private func applyLocalState(_ next: ProfileState, skipPostsBootstrap: Bool = false) {
        var next = next
        next.lastUpdated = Date()
        next.isRefreshing = state.isRefreshing
        state = next
        contentStore.applyBootstrap(next)
        if shellViewModel == nil {
            syncShellIfNeeded()
        } else if skipPostsBootstrap {
            shellViewModel?.applyExcludingPosts(state: next)
        } else {
            shellViewModel?.apply(state: next)
        }
    }
    private func bootstrapIfNeeded(force: Bool) {
        if bootstrapTask != nil, !force { return }
        bootstrapTask?.cancel()
        bootstrapTask = Task { [weak self] in
            await self?.performBootstrap(force: force)
        }
    }

    private func performBootstrap(force: Bool) async {
        if !force, state.didBootstrap { return }

        if state.profile == nil {
            state.phase = .loading
            contentStore.applyBootstrap(state)
        }

        let next = await ProfileBootstrap.load(
            .init(
                target: target,
                profiles: data.profiles,
                trades: data.trades,
                achievements: data.achievements,
                feed: data.feed,
                rooms: data.rooms,
                session: data.session,
                detailCache: data.detailCache,
                engagementStore: data.engagementStore,
                rpc: data.rpc,
                force: force
            )
        )
        guard !Task.isCancelled else { return }
        if force {
            // Recreate section VMs so Stage 2 reloads once per tab after refresh.
            shellViewModel = nil
        }
        publish(next)
        bootstrapTask = nil
    }

    private func publish(_ next: ProfileState) {
        var next = next
        if isOwnerTarget {
            next = OwnerProfileOptimisticStore.shared.merging(into: next)
        }
        if next.phase == .loaded {
            next.lastUpdated = Date()
        }
        // Preserve in-flight refresh flag across publish.
        next.isRefreshing = state.isRefreshing
        state = next
        contentStore.applyBootstrap(next)
        syncShellIfNeeded()
        activateShellForLaunch()

        // Prefetch engagement only after the default trades section has data.
        if next.didLoadTrades, let trades = shellViewModel?.trades {
            trades.prefetchEngagement(for: next.trades.map(\.id))
        }
    }

    private func seedOwnerCacheIfNeeded(from currentUserProfile: CurrentUserProfileStore) {
        guard case .currentUser = target else { return }
        if let profile = currentUserProfile.profile {
            data.detailCache.seed(profile)
        }
        if let stats = currentUserProfile.stats, stats.hasLoadedHeaderMetrics {
            data.detailCache.seed(stats: stats)
        }
    }
}

extension ProfileScreenViewModel: ScreenLifecycle {}
