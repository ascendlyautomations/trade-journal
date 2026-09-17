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
    private var isReconcilingFromDisk = false

    var pinnedContent: [ProfilePinnedItem] { state.pinnedContent }
    var showsPinReplaceSheet = false
    var showsManagePinnedSheet = false
    private(set) var pendingPinRequest: ProfilePinRequest?
    private(set) var pendingPinPreview: ProfilePinnedPreview?
    private var pinnedMutationInFlight = false

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
        var loading = ProfileState()
        loading.phase = .loading
        content.applyBootstrap(loading)
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
        shellViewModel?.activateSelected()
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

    func isPinned(contentType: ProfilePinnedContentType, contentID: String) -> Bool {
        state.pinnedContent.contains {
            $0.contentType == contentType && $0.contentID == contentID
        }
    }

    func requestPin(
        contentType: ProfilePinnedContentType,
        contentID: String,
        preview: ProfilePinnedPreview
    ) {
        guard contentStore.isOwner, !pinnedMutationInFlight else { return }
        let request = ProfilePinRequest(
            contentType: contentType,
            contentID: contentID,
            replacePosition: nil
        )
        if isPinned(contentType: contentType, contentID: contentID) {
            Task { await unpin(contentType: contentType, contentID: contentID) }
            return
        }
        if state.pinnedContent.count >= 3 {
            pendingPinRequest = request
            pendingPinPreview = preview
            showsPinReplaceSheet = true
            return
        }
        Task { await performPin(request: request, preview: preview, replacePosition: nil) }
    }

    func confirmReplacePin(at position: Int) {
        guard let request = pendingPinRequest, let preview = pendingPinPreview else { return }
        showsPinReplaceSheet = false
        pendingPinRequest = nil
        pendingPinPreview = nil
        Task { await performPin(request: request, preview: preview, replacePosition: position) }
    }

    func cancelReplacePin() {
        showsPinReplaceSheet = false
        pendingPinRequest = nil
        pendingPinPreview = nil
    }

    func unpin(contentType: ProfilePinnedContentType, contentID: String) async {
        guard contentStore.isOwner, !pinnedMutationInFlight else { return }
        let previous = state.pinnedContent
        applyPinnedContentOptimistic(
            ProfilePinnedMutation.remove(
                contentType: contentType,
                contentID: contentID,
                from: previous
            )
        )
        pinnedMutationInFlight = true
        defer { pinnedMutationInFlight = false }
        do {
            let authoritative = try await ProfilePinnedContentRepository.unpin(
                contentType: contentType,
                contentID: contentID,
                supabase: data.supabase
            )
            applyPinnedContent(authoritative)
            ExperienceHaptics.play(.success)
        } catch {
            applyPinnedContent(previous)
            ExperienceHaptics.play(.warning)
        }
    }

    func openPinnedItem(_ item: ProfilePinnedItem) {
        ExperienceHaptics.play(.selection)
        switch item.contentType {
        case .trade:
            if let id = item.tradeID {
                navigationCoordinator.open(.profile(.trade(id)))
            }
        case .profilePost:
            if let id = item.postID {
                navigationCoordinator.open(.profile(.post(id)))
            }
        case .achievement:
            if let id = item.achievementID {
                navigationCoordinator.open(.profile(.achievement(id)))
            }
        }
    }

    func movePinnedItemUp(_ item: ProfilePinnedItem) {
        guard item.position > 1 else { return }
        Task { await reorderPinned(from: item.position, to: item.position - 1) }
    }

    func movePinnedItemDown(_ item: ProfilePinnedItem) {
        guard item.position < state.pinnedContent.count else { return }
        Task { await reorderPinned(from: item.position, to: item.position + 1) }
    }

    private func performPin(
        request: ProfilePinRequest,
        preview: ProfilePinnedPreview,
        replacePosition: Int?
    ) async {
        guard contentStore.isOwner else { return }
        let previous = state.pinnedContent
        var optimisticRequest = request
        optimisticRequest.replacePosition = replacePosition
        applyPinnedContentOptimistic(
            ProfilePinnedMutation.insert(
                request: optimisticRequest,
                preview: preview,
                into: previous
            )
        )
        pinnedMutationInFlight = true
        defer { pinnedMutationInFlight = false }
        do {
            let authoritative = try await ProfilePinnedContentRepository.pin(
                request: optimisticRequest,
                supabase: data.supabase
            )
            applyPinnedContent(authoritative)
            ExperienceHaptics.play(.success)
        } catch {
            applyPinnedContent(previous)
            ExperienceHaptics.play(.warning)
        }
    }

    private func reorderPinned(from: Int, to: Int) async {
        guard contentStore.isOwner, !pinnedMutationInFlight else { return }
        let previous = state.pinnedContent
        applyPinnedContentOptimistic(
            ProfilePinnedMutation.swapPositions(from: from, to: to, in: previous)
        )
        pinnedMutationInFlight = true
        defer { pinnedMutationInFlight = false }
        do {
            let authoritative = try await ProfilePinnedContentRepository.reorder(
                fromPosition: from,
                toPosition: to,
                supabase: data.supabase
            )
            applyPinnedContent(authoritative)
            ExperienceHaptics.play(.success)
        } catch {
            applyPinnedContent(previous)
            ExperienceHaptics.play(.warning)
        }
    }

    private func applyPinnedContent(_ items: [ProfilePinnedItem]) {
        guard state.pinnedContent != items else { return }
        var next = state
        next.pinnedContent = items
        state = next
        contentStore.applyPinnedContent(items)
    }

    private func applyPinnedContentOptimistic(_ items: [ProfilePinnedItem]) {
        var next = state
        next.pinnedContent = items
        state = next
        contentStore.applyPinnedContent(items)
    }

    // MARK: - Optimistic owner mutations (no network)

    /// Called by ``OwnerProfileOptimisticStore`` when the owner Profile screen is registered.
    func absorbOwnerOptimisticOverlays() {
        guard isOwnerTarget else { return }
        let merged = OwnerProfileOptimisticStore.shared.merging(into: state)
        guard merged != state else { return }
        let skipPosts = shellViewModel?.posts?.hasAuthoritativePayload == true
        let skipClips = shellViewModel?.clips?.hasAuthoritativePayload == true
        applyLocalState(merged, skipPostsBootstrap: skipPosts, skipClipsBootstrap: skipClips)
        if skipPosts, let visible = shellViewModel?.posts?.items {
            syncPostsFromSection(visible)
        }
        if skipClips, let visible = shellViewModel?.clips?.items {
            syncClipsFromSection(visible)
        }
    }

    func applyOptimisticPost(_ post: Post) {
        guard isOwnerTarget else { return }
        guard matchesOwner(post.authorProfileID) else { return }
        data.detailCache.seed(post)
        Task { await persistMutationPatch { viewerID in
            ProfilePersistedCacheCoordinator.patchPost(post, viewerID: viewerID)
        } }

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
        var next = state
        next.posts = posts
        next.didLoadPosts = true
        next.lastUpdated = Date()
        guard next != state else { return }
        state = next
        shellViewModel?.adoptLatestState(next)
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

    /// Keeps ``ProfileState.clips`` aligned with the section VM after authoritative refresh.
    func syncClipsFromSection(_ clips: [Reel]) {
        guard isOwnerTarget else { return }
        var next = state
        next.clips = clips
        next.didLoadClips = true
        next.lastUpdated = Date()
        guard next != state else { return }
        state = next
        shellViewModel?.adoptLatestState(next)
    }

    /// Keeps ``ProfileState.trades`` aligned with the section VM after journal create/update.
    func syncTradesFromSection(_ trades: [Trade]) {
        guard isOwnerTarget else { return }
        var next = state
        next.trades = trades
        next.didLoadTrades = true
        next.lastUpdated = Date()
        guard next != state else { return }
        state = next
        shellViewModel?.adoptLatestState(next)
    }

    func syncAchievementsFromSection(_ achievements: [Achievement]) {
        guard isOwnerTarget else { return }
        var next = state
        next.achievements = achievements
        next.didLoadAchievements = true
        next.lastUpdated = Date()
        guard next != state else { return }
        state = next
        shellViewModel?.adoptLatestState(next)
    }

    /// Authoritative journal trade — update Profile state + trades section without stale bootstrap overwrite.
    func applyJournalTradeMutation(_ trade: Trade) {
        guard isOwnerTarget else { return }
        guard matchesOwner(trade.ownerProfileID) else { return }

        syncShellIfNeeded()
        shellViewModel?.ensureTradesSection()

        if trade.visibility == .public {
            data.detailCache.seed(trade)
            shellViewModel?.trades?.noteJournalMutationSucceeded(
                trade,
                preservingExisting: preferredTradesBase()
            )

            var next = state
            next.trades = OwnerProfileOptimisticStore.upserting(trade, into: preferredTradesBase())
            if next.phase == .idle || next.phase == .loading {
                applyLocalState(next, skipTradesBootstrap: true)
            } else {
                next.phase = .loaded
                next.didBootstrap = true
                applyLocalState(next, skipTradesBootstrap: true)
            }

            if let visible = shellViewModel?.trades?.items {
                syncTradesFromSection(visible)
            }
        } else {
            var next = state
            next.trades.removeAll { $0.id == trade.id }
            applyLocalState(next, skipTradesBootstrap: true)
            shellViewModel?.trades?.handleJournalMutation()
        }
    }

    private func preferredTradesBase() -> [Trade] {
        if let tradesVM = shellViewModel?.trades, !tradesVM.items.isEmpty {
            return tradesVM.items
        }
        if !state.trades.isEmpty {
            return state.trades
        }
        return []
    }

    private func ownerPublicTradePreserveIDs(for profileID: ProfileID?) -> Set<TradeID> {
        guard let profileID else { return [] }
        return Set(
            (SessionOwnerTradesStore.shared.cached(for: profileID) ?? [])
                .filter { $0.visibility == .public }
                .map(\.id)
        )
    }

    private func preferredClipsBase() -> [Reel] {
        if let clipsVM = shellViewModel?.clips, !clipsVM.items.isEmpty {
            return clipsVM.items
        }
        if !state.clips.isEmpty {
            return state.clips
        }
        return OwnerProfileOptimisticStore.shared.reels.filter {
            matchesOwner($0.authorProfileID)
                && OwnerProfileOptimisticStore.isListedOnOwnerProfile($0)
        }
    }

    private func syncSectionSnapshotsIntoState() {
        if let postsVM = shellViewModel?.posts, postsVM.hasAuthoritativePayload {
            syncPostsFromSection(postsVM.items)
        }
        if let clipsVM = shellViewModel?.clips, clipsVM.hasAuthoritativePayload {
            syncClipsFromSection(clipsVM.items)
        }
        if let tradesVM = shellViewModel?.trades, tradesVM.hasAuthoritativePayload {
            syncTradesFromSection(tradesVM.items)
        }
        if let achievementsVM = shellViewModel?.achievements, achievementsVM.hasAuthoritativePayload {
            syncAchievementsFromSection(achievementsVM.items)
        }
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
        Task { await persistMutationPatch { viewerID in
            ProfilePersistedCacheCoordinator.patchReel(reel, viewerID: viewerID)
        } }

        syncShellIfNeeded()
        shellViewModel?.ensureClipsSection()

        let baseClips = preferredClipsBase()
        var next = state
        next.clips = OwnerProfileOptimisticStore.upserting(reel, into: baseClips)

        shellViewModel?.clips?.notePublishSucceeded(
            reel,
            preservingExisting: baseClips
        )

        if next.phase == .idle || next.phase == .loading {
            applyLocalState(next, skipClipsBootstrap: true)
        } else {
            next.phase = .loaded
            next.didBootstrap = true
            applyLocalState(next, skipClipsBootstrap: true)
        }

        if let visible = shellViewModel?.clips?.items {
            syncClipsFromSection(visible)
        }
    }

    func applyOptimisticAchievement(_ achievement: Achievement) {
        guard isOwnerTarget else { return }
        guard matchesOwner(achievement.ownerProfileID) else { return }
        data.detailCache.seed(achievement)
        Task { await persistMutationPatch { viewerID in
            ProfilePersistedCacheCoordinator.patchAchievement(achievement, viewerID: viewerID)
        } }
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
        Task { await persistMutationPatch { viewerID in
            if let owner = state.profileID {
                ProfilePersistedCacheCoordinator.removePost(id: id, owner: owner, viewerID: viewerID)
            }
        } }
        syncShellIfNeeded()
        shellViewModel?.posts?.noteDeleteSucceeded(id: id)
        var next = state
        next.posts.removeAll { $0.id == id }
        next.pinnedContent = ProfilePinnedMutation.remove(
            contentType: .profilePost,
            contentID: id.rawValue,
            from: next.pinnedContent
        )
        applyLocalState(next, skipPostsBootstrap: true)
        if let visible = shellViewModel?.posts?.items {
            syncPostsFromSection(visible)
        }
    }

    func applyOptimisticPinnedRemoval(
        contentType: ProfilePinnedContentType,
        contentID: String
    ) {
        guard isOwnerTarget, isPinned(contentType: contentType, contentID: contentID) else { return }
        applyPinnedContentOptimistic(
            ProfilePinnedMutation.remove(
                contentType: contentType,
                contentID: contentID,
                from: state.pinnedContent
            )
        )
    }

    func applyOptimisticReelRemoval(id: ReelID) {
        guard isOwnerTarget else { return }
        data.detailCache.removeReel(id: id)
        Task { await persistMutationPatch { viewerID in
            if let owner = state.profileID {
                ProfilePersistedCacheCoordinator.removeReel(id: id, owner: owner, viewerID: viewerID)
            }
        } }
        syncShellIfNeeded()
        shellViewModel?.clips?.noteDeleteSucceeded(id: id)
        var next = state
        next.clips.removeAll { $0.id == id }
        applyLocalState(next, skipClipsBootstrap: true)
        if let visible = shellViewModel?.clips?.items {
            syncClipsFromSection(visible)
        }
    }

    func applyJournalTradeDeletion(id: TradeID, owner: ProfileID) {
        guard isOwnerTarget, matchesOwner(owner) else { return }
        applyOptimisticPinnedRemoval(contentType: .trade, contentID: id.rawValue)
        data.detailCache.removeTrade(id: id)
        Task { await persistMutationPatch { viewerID in
            ProfilePersistedCacheCoordinator.removeTrade(id: id, owner: owner, viewerID: viewerID)
        } }
        syncShellIfNeeded()
        shellViewModel?.ensureTradesSection()
        shellViewModel?.trades?.handleJournalMutation()
        var next = state
        next.trades.removeAll { $0.id == id }
        applyLocalState(next, skipTradesBootstrap: true)
        if let visible = shellViewModel?.trades?.items {
            syncTradesFromSection(visible)
        }
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

    private func applyLocalState(
        _ next: ProfileState,
        skipPostsBootstrap: Bool = false,
        skipClipsBootstrap: Bool = false,
        skipTradesBootstrap: Bool = false
    ) {
        var next = next
        next.lastUpdated = Date()
        next.isRefreshing = state.isRefreshing
        state = next
        contentStore.applyBootstrap(next)
        if shellViewModel == nil {
            syncShellIfNeeded()
        } else if skipPostsBootstrap && skipClipsBootstrap && skipTradesBootstrap {
            shellViewModel?.applyExcludingPostsClipsAndTrades(state: next)
        } else if skipPostsBootstrap && skipClipsBootstrap {
            shellViewModel?.applyExcludingPostsAndClips(state: next)
        } else if skipPostsBootstrap && skipTradesBootstrap {
            shellViewModel?.applyExcludingPostsAndTrades(state: next)
        } else if skipClipsBootstrap && skipTradesBootstrap {
            shellViewModel?.applyExcludingClipsAndTrades(state: next)
        } else if skipPostsBootstrap {
            shellViewModel?.applyExcludingPosts(state: next)
        } else if skipClipsBootstrap {
            shellViewModel?.applyExcludingClips(state: next)
        } else if skipTradesBootstrap {
            shellViewModel?.applyExcludingTrades(state: next)
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

        let targetProfileID = await resolveTargetProfileID()
        let viewerID = await data.session.currentUserID.map { ProfileID($0.rawValue) }

        if !force, !isReconcilingFromDisk, let viewerID, let targetProfileID {
            let hydrateStart = Date()
            if let diskState = ProfilePersistedCacheCoordinator.hydrate(
                viewerID: viewerID,
                targetProfileID: targetProfileID,
                detailCache: data.detailCache,
                engagementStore: data.engagementStore,
                blockedPeers: FeedBlockedAuthorsFilter.shared.blockedPeerIDs
            ) {
                publish(diskState, source: .disk)
                #if DEBUG
                ProfilePersistentCacheProbe.recordDiskHit(
                    profileID: targetProfileID.rawValue,
                    ageMs: Int(Date().timeIntervalSince(diskState.lastUpdated ?? Date()) * 1000),
                    firstRenderMs: Int(Date().timeIntervalSince(hydrateStart) * 1000)
                )
                #endif
                isReconcilingFromDisk = true
                await performBootstrap(force: true)
                isReconcilingFromDisk = false
                bootstrapTask = nil
                return
            }

            if case .currentUser = target,
               let ownerState = buildOwnerPrefetchState(viewerID: viewerID, targetProfileID: targetProfileID)
            {
                publish(ownerState, source: .disk)
                #if DEBUG
                ProfilePersistentCacheProbe.recordDiskHit(
                    profileID: targetProfileID.rawValue,
                    ageMs: 0,
                    firstRenderMs: Int(Date().timeIntervalSince(hydrateStart) * 1000)
                )
                #endif
                isReconcilingFromDisk = true
                await performBootstrap(force: true)
                isReconcilingFromDisk = false
                bootstrapTask = nil
                return
            }
        }

        if state.profile == nil {
            state.phase = .loading
            contentStore.applyBootstrap(state)
        }

        let existingForReconcile = isReconcilingFromDisk ? state : ProfileState()
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
        if force, !isReconcilingFromDisk {
            // Recreate section VMs so Stage 2 reloads once per tab after refresh.
            shellViewModel = nil
        }

        if isReconcilingFromDisk, existingForReconcile.profile != nil {
            if next.profile == nil || next.phase == .failed {
                var preserved = existingForReconcile
                preserved.errorMessage = next.errorMessage
                publish(preserved, source: .disk)
                bootstrapTask = nil
                return
            }
            let reconcileStart = Date()
            let merged = ProfilePersistentReconcile.reconcileProfileState(
                existing: existingForReconcile,
                incoming: next,
                preservePublicTradeIDs: ownerPublicTradePreserveIDs(
                    for: existingForReconcile.profileID ?? next.profileID
                )
            )
            publish(merged, source: .network)
            #if DEBUG
            ProfilePersistentCacheProbe.recordReconcile(
                inserted: 0,
                updated: 0,
                removed: 0,
                durationMs: Int(Date().timeIntervalSince(reconcileStart) * 1000)
            )
            #endif
        } else {
            publish(next, source: .network)
        }
        bootstrapTask = nil
    }

    private enum PublishSource {
        case disk
        case network
    }

    private func publish(_ next: ProfileState, source: PublishSource) {
        var next = ProfilePersistentReconcile.preservingAbsentSectionLoads(
            incoming: next,
            existing: state
        )
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

        Task {
            await persistProfileStateIfPossible(next, source: source)
        }
    }

    private func persistProfileStateIfPossible(_ snapshot: ProfileState, source: PublishSource) async {
        guard snapshot.phase == .loaded,
              let userID = await data.session.currentUserID,
              let targetID = snapshot.profileID ?? contentStore.resolvedProfileID
        else { return }
        let viewerID = ProfileID(userID.rawValue)
        ProfilePersistedCacheCoordinator.persist(
            viewerID: viewerID,
            targetProfileID: targetID,
            state: snapshot,
            engagementStore: data.engagementStore
        )
        #if DEBUG
        if source == .network {
            ProfilePersistentCacheProbe.recordNetworkBootstrap(profileID: targetID.rawValue)
        }
        #endif
    }

    private func resolveTargetProfileID() async -> ProfileID? {
        switch target {
        case .currentUser:
            guard let userID = await data.session.currentUserID else { return nil }
            return ProfileID(userID.rawValue)
        case .profile(let id):
            return id
        }
    }

    private func buildOwnerPrefetchState(
        viewerID: ProfileID,
        targetProfileID: ProfileID
    ) -> ProfileState? {
        guard viewerID == targetProfileID else { return nil }
        guard let profile = data.detailCache.profile(id: viewerID) else { return nil }
        var prefetched = ProfileState()
        prefetched.phase = .loaded
        prefetched.profileID = viewerID
        prefetched.profile = profile
        prefetched.stats = data.detailCache.stats(for: viewerID)
        prefetched.isOwner = true
        prefetched.canViewTrades = true
        prefetched.didBootstrap = true
        prefetched.didResolveTradeRoom = data.detailCache.hasResolvedOwnedTradeRoom(for: viewerID)
        prefetched.ownedTradeRoom = data.detailCache.ownedTradeRoom(for: viewerID)
        if let trades = ProfilePersistedCacheCoordinator.hydrateOwnerTradesIfNeeded(
            ownerID: viewerID,
            detailCache: data.detailCache
        ) {
            prefetched.trades = trades.filter { $0.visibility == .public }
            prefetched.didLoadTrades = !prefetched.trades.isEmpty
            prefetched.tradesNextCursor = prefetched.trades.count >= 30 ? "disk" : nil
        }
        return prefetched
    }

    private func seedOwnerCacheIfNeeded(from currentUserProfile: CurrentUserProfileStore) {
        guard case .currentUser = target else { return }
        if let profile = currentUserProfile.profile {
            data.detailCache.seed(profile)
        }
        if let stats = currentUserProfile.stats, stats.hasLoadedHeaderMetrics {
            data.detailCache.seed(stats: stats)
        }
        if let profile = currentUserProfile.profile {
            Task {
                guard let userID = await data.session.currentUserID else { return }
                let viewerID = ProfileID(userID.rawValue)
                SocialEntityDiskCache.saveProfile(profile, viewerID: viewerID)
            }
        }
    }

    private func persistMutationPatch(_ block: (ProfileID) -> Void) async {
        guard let userID = await data.session.currentUserID else { return }
        block(ProfileID(userID.rawValue))
        await persistProfileStateIfPossible(state, source: .network)
    }
}

extension ProfileScreenViewModel: ScreenLifecycle {}
