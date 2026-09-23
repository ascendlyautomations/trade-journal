import Foundation
import Observation

@Observable
@MainActor
final class ClipsContainerViewModel {
    private(set) var state: ProfileSectionLoadState = .idle
    private(set) var items: [Reel] = []
    private(set) var nextCursor: String?

    let profileOwnerID: ProfileID
    private(set) var isOwner: Bool
    private let feed: any FeedRepository
    private let rpc: (any RPCClient)?
    private let navigationCoordinator: NavigationCoordinator
    private let detailCache: DetailPresentationCache
    private let engagementStore: EngagementStore?
    private var loadTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var isLoadingMore = false
    private var paginationGeneration = 0
    private var hasLoaded = false
    private var isScreenOwned = false
    private var awaitingScreenBootstrap = false
    private let initialLoadFailureGrace = ProfileSectionFailureGrace()
    private var syncGeneration: UInt64 = 0
    private var trackedPublishedReelID: ReelID?
    /// Non-owner Profile — sync clips into persisted profile snapshot (owner uses ``OwnerProfileOptimisticStore``).
    var clipsSectionPersistenceHandler: (([Reel]) -> Void)?

    var hasAuthoritativePayload: Bool { hasLoaded }

    init(
        profileID: ProfileID,
        feed: any FeedRepository,
        rpc: (any RPCClient)? = nil,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore? = nil,
        isOwner: Bool = true
    ) {
        self.profileOwnerID = profileID
        self.isOwner = isOwner
        self.feed = feed
        self.rpc = rpc
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        self.engagementStore = engagementStore
    }

    func prefetchEngagement(for reelIDs: [ReelID]) {
        let targets = reelIDs.map { InteractionTarget.reel($0) }
        if targets.isEmpty {
            EngagementRealtimeSession.shared.updateRetention(
                ownerKey: "profile-clips:\(profileOwnerID.rawValue)",
                targets: []
            )
            return
        }
        engagementStore?.prefetch(targets)
        EngagementRealtimeSession.shared.updateRetention(
            ownerKey: "profile-clips:\(profileOwnerID.rawValue)",
            targets: Set(targets)
        )
    }

    func applyBootstrap(_ snapshot: ProfileState) {
        if snapshot.didBootstrap || snapshot.phase == .loaded {
            isScreenOwned = true
        }
        awaitingScreenBootstrap = ProfileSectionInitialLoad.awaitingScreenBootstrap(
            isScreenOwned: isScreenOwned,
            snapshot: snapshot,
            didLoadSection: snapshot.didLoadClips,
            sectionItemsEmpty: snapshot.clips.isEmpty,
            localItemsEmpty: items.isEmpty
        )
        let beforeCount = items.count
        guard snapshot.didLoadClips || !snapshot.clips.isEmpty else {
            let plan = ProfileSectionInitialLoad.planWhenBootstrapOmitsSectionPayload(
                snapshot: snapshot,
                hasLoaded: hasLoaded,
                itemsEmpty: items.isEmpty,
                itemCount: items.count,
                currentState: state,
                awaitingScreenBootstrap: awaitingScreenBootstrap
            )
            ProfileSectionInitialLoad.applyBootstrapMissingSectionPlan(
                plan,
                setState: { [self] next in state = next },
                kickDeferredLoad: { [self] in loadIfNeeded() }
            )
            return
        }

        awaitingScreenBootstrap = false
        initialLoadFailureGrace.cancel()

        if hasLoaded {
            if snapshot.clips.isEmpty {
                if snapshot.didLoadClips {
                    items = []
                    detailCache.seed(reels: [])
                    state = .empty
                    prefetchEngagement(for: [])
                }
                return
            }
            items = ProfileSectionSupport.reconcileLoadedSnapshot(
                snapshot: snapshot.clips,
                loaded: items
            )
            #if DEBUG
            ProfileClipsSync.logReconciled(
                beforeCount: beforeCount,
                snapshotCount: snapshot.clips.count,
                afterCount: items.count
            )
            ProfileClipsSync.logUIVisibleCount(items.count)
            #endif
            detailCache.seed(reels: items)
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
            return
        }

        let reconciled = ProfileSectionSupport.reconcileSectionItems(
            snapshotItems: snapshot.clips,
            loadedItems: items,
            hasLoaded: hasLoaded,
            didLoadAuthoritative: snapshot.didLoadClips
        )
        items = reconciled.items
        hasLoaded = reconciled.hasLoaded
        #if DEBUG
        ProfileClipsSync.logReconciled(
            beforeCount: beforeCount,
            snapshotCount: snapshot.clips.count,
            afterCount: items.count
        )
        ProfileClipsSync.logUIVisibleCount(items.count)
        #endif
        detailCache.seed(reels: items)
        state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        prefetchEngagement(for: items.map(\.id))
    }

    /// Owner delete — drop from grid immediately (detail overflow + context menus).
    func noteDeleteSucceeded(id: ReelID) {
        items.removeAll { $0.id == id }
        detailCache.removeReel(id: id)
        RepositoryRequestFlight.shared.invalidate(
            prefix: "feed.profileReels:\(profileOwnerID.rawValue)"
        )
        state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        prefetchEngagement(for: items.map(\.id))
        notifyClipsSectionPersistence(items)
    }

    /// Owner publish — upsert immediately, then refresh using the same path as manual reload.
    func notePublishSucceeded(_ reel: Reel, preservingExisting existingItems: [Reel] = []) {
        guard reel.authorProfileID == profileOwnerID else { return }
        guard OwnerProfileOptimisticStore.isListedOnOwnerProfile(reel) else { return }
        trackedPublishedReelID = reel.id
        let visibleBefore = items.count
        let baseline = items.isEmpty ? existingItems : items
        items = OwnerProfileOptimisticStore.upserting(reel, into: baseline)
        hasLoaded = true
        detailCache.seed(reels: items)
        detailCache.seed(reel)
        state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        prefetchEngagement(for: items.map(\.id))

        syncGeneration &+= 1
        let generation = syncGeneration
        #if DEBUG
        ProfileClipsSync.logPublishSucceeded(
            id: reel.id.rawValue,
            visibleBefore: visibleBefore,
            optimisticAfter: items.count
        )
        ProfileClipsSync.logAuthoritativeRefreshStarted(generation: generation)
        ProfileClipsSync.logUIVisibleCount(items.count)
        #endif

        loadTask?.cancel()
        loadTask = Task { await performLoad(generation: generation) }
    }

    func loadIfNeeded() {
        guard !hasLoaded, loadTask == nil else { return }
        if awaitingScreenBootstrap {
            if items.isEmpty {
                state = .loading
            }
            return
        }
        syncGeneration &+= 1
        let generation = syncGeneration
        loadTask = Task { await performLoad(generation: generation) }
    }

    func refresh() async {
        syncGeneration &+= 1
        let generation = syncGeneration
        loadTask?.cancel()
        cancelLoadMore(reason: "refresh")
        await performLoad(generation: generation)
    }

    func loadMoreIfNeeded() async {
        guard let lastID = items.last?.id else { return }
        await loadMoreIfNeeded(currentReelID: lastID)
    }

    func loadMoreIfNeeded(currentReelID: ReelID?) async {
        guard hasLoaded, nextCursor != nil, loadMoreTask == nil, !isLoadingMore else { return }
        guard let currentReelID, items.last?.id == currentReelID else { return }
        let cursor = nextCursor
        let generation = paginationGeneration
        isLoadingMore = true
        loadMoreTask = Task { @MainActor in
            defer {
                isLoadingMore = false
                loadMoreTask = nil
            }
            await performLoadMore(cursor: cursor, generation: generation)
        }
    }

    private func cancelLoadMore(reason: String) {
        paginationGeneration &+= 1
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMore = false
        _ = reason
    }

    func openClip(_ reel: Reel) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(reel)
        navigationCoordinator.open(.profile(.reel(reel.id)))
    }

    func addClip() {
        navigationCoordinator.openCompose(.reel)
    }

    private func performLoad(generation: UInt64) async {
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileOwnerID) {
            guard generation == syncGeneration else {
                #if DEBUG
                ProfileClipsSync.logStaleResponseDropped(
                    generation: generation,
                    currentGeneration: syncGeneration
                )
                #endif
                loadTask = nil
                return
            }
            hasLoaded = true
            let overlay = OwnerProfileOptimisticStore.shared.reels.filter {
                $0.authorProfileID == profileOwnerID
                    && OwnerProfileOptimisticStore.isListedOnOwnerProfile($0)
            }
            let serverMerged = OwnerProfileOptimisticStore.merging(
                overlay: overlay,
                into: ProfileClipFixtures.samples(owner: profileOwnerID)
            )
            items = OwnerProfileOptimisticStore.merging(overlay: serverMerged, into: items)
            detailCache.seed(reels: items)
            detailCache.seed(trades: ProfileClipFixtures.linkedTrades(for: items))
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
            #if DEBUG
            ProfileClipsSync.logAuthoritativeReturned(generation: generation, count: items.count)
            ProfileClipsSync.logUIVisibleCount(items.count)
            #endif
            notifyClipsSectionPersistence(items)
            loadTask = nil
            return
        }

        state = items.isEmpty ? .loading : state
        paginationGeneration &+= 1
        initialLoadFailureGrace.cancel()
        do {
            let pageReels: [Reel]
            let cursor: String?
            if BackendV2FeatureFlags.isEnabled(.profile), let rpc {
                let applied = try await ProfileTabBootstrapLoader.load(
                    tab: .reels,
                    profileID: profileOwnerID,
                    rpc: rpc,
                    detailCache: nil,
                    cursor: nil
                )
                pageReels = applied.reels ?? []
                cursor = applied.nextCursor
                if let linkedTrades = applied.reelLinkedTrades, !linkedTrades.isEmpty {
                    detailCache.seed(trades: linkedTrades)
                }
            } else {
                let result = try await feed.profileReels(for: profileOwnerID)
                pageReels = result.reels
                cursor = nil
                if !result.embeddedTrades.isEmpty {
                    detailCache.seed(trades: result.embeddedTrades)
                }
            }
            guard !Task.isCancelled else { return }
            guard generation == syncGeneration else {
                #if DEBUG
                ProfileClipsSync.logStaleResponseDropped(
                    generation: generation,
                    currentGeneration: syncGeneration
                )
                #endif
                loadTask = nil
                return
            }
            let overlay = OwnerProfileOptimisticStore.shared.reels.filter {
                $0.authorProfileID == profileOwnerID
                    && OwnerProfileOptimisticStore.isListedOnOwnerProfile($0)
            }
            let beforeCount = items.count
            let serverMerged = OwnerProfileOptimisticStore.merging(overlay: overlay, into: pageReels)
            items = OwnerProfileOptimisticStore.merging(overlay: serverMerged, into: [])
            nextCursor = cursor
            detailCache.seed(reels: items)
            hasLoaded = true
            initialLoadFailureGrace.cancel()
            #if DEBUG
            ProfileClipsSync.logFetch(
                userID: profileOwnerID.rawValue,
                count: pageReels.count,
                newPublishedReelID: trackedPublishedReelID?.rawValue
            )
            for reel in items {
                ProfileClipsSync.logReel(
                    id: reel.id.rawValue,
                    videoPresent: !reel.video.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    thumbnailPresent: reel.thumbnail.map {
                        !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    } ?? false
                )
            }
            if let trackedPublishedReelID {
                ProfileClipsSync.logNewPublishedReelFound(
                    items.contains(where: { $0.id == trackedPublishedReelID }),
                    reelID: trackedPublishedReelID.rawValue
                )
            }
            ProfileClipsSync.logAuthoritativeReturned(generation: generation, count: pageReels.count)
            ProfileClipsSync.logReconciled(
                beforeCount: beforeCount,
                snapshotCount: pageReels.count,
                afterCount: items.count
            )
            ProfileClipsSync.logUIVisibleCount(items.count)
            #endif
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
            notifyClipsSectionPersistence(items)
        } catch {
            guard !Task.isCancelled else { return }
            guard generation == syncGeneration else {
                #if DEBUG
                ProfileClipsSync.logStaleResponseDropped(
                    generation: generation,
                    currentGeneration: syncGeneration
                )
                #endif
                loadTask = nil
                return
            }
            if items.isEmpty {
                if awaitingScreenBootstrap {
                    state = .loading
                } else {
                    let message = ProfileSectionSupport.message(for: error)
                    let failedGeneration = generation
                    initialLoadFailureGrace.scheduleIfNeeded(message: message) { [weak self] in
                        guard let self else { return false }
                        return !hasLoaded
                            && items.isEmpty
                            && syncGeneration == failedGeneration
                            && !awaitingScreenBootstrap
                    } present: { [weak self] message in
                        self?.state = .failed(message: message)
                    }
                }
            }
        }
        loadTask = nil
    }

    private func notifyClipsSectionPersistence(_ clips: [Reel]) {
        if isOwner {
            OwnerProfileOptimisticStore.shared.syncOwnerClipsState(clips)
        } else {
            clipsSectionPersistenceHandler?(clips)
        }
    }

    private func performLoadMore(cursor: String?, generation: Int) async {
        guard generation == paginationGeneration else { return }
        do {
            let pageReels: [Reel]
            let newCursor: String?
            if BackendV2FeatureFlags.isEnabled(.profile), let rpc {
                let applied = try await ProfileTabBootstrapLoader.load(
                    tab: .reels,
                    profileID: profileOwnerID,
                    rpc: rpc,
                    detailCache: nil,
                    cursor: cursor
                )
                pageReels = applied.reels ?? []
                newCursor = applied.nextCursor
                if let linkedTrades = applied.reelLinkedTrades, !linkedTrades.isEmpty {
                    detailCache.seed(trades: linkedTrades)
                }
            } else {
                return
            }
            guard generation == paginationGeneration, !Task.isCancelled else { return }
            if pageReels.isEmpty {
                nextCursor = nil
                return
            }
            appendUniqueReels(pageReels)
            nextCursor = newCursor
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: pageReels.map(\.id))
        } catch {
            guard generation == paginationGeneration else { return }
        }
    }

    private func appendUniqueReels(_ pageItems: [Reel]) {
        let existing = Set(items.map(\.id))
        let fresh = pageItems.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else {
            nextCursor = nil
            return
        }
        items.append(contentsOf: fresh)
        detailCache.seed(reels: items)
    }
}
