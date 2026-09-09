import Foundation
import Observation

@Observable
@MainActor
final class ClipsContainerViewModel {
    private(set) var state: ProfileSectionLoadState = .idle
    private(set) var items: [Reel] = []

    let profileOwnerID: ProfileID
    private(set) var isOwner: Bool
    private let feed: any FeedRepository
    private let navigationCoordinator: NavigationCoordinator
    private let detailCache: DetailPresentationCache
    private let engagementStore: EngagementStore?
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var isScreenOwned = false
    private var syncGeneration: UInt64 = 0
    private var trackedPublishedReelID: ReelID?

    var hasAuthoritativePayload: Bool { hasLoaded }

    init(
        profileID: ProfileID,
        feed: any FeedRepository,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore? = nil,
        isOwner: Bool = true
    ) {
        self.profileOwnerID = profileID
        self.isOwner = isOwner
        self.feed = feed
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        self.engagementStore = engagementStore
    }

    func prefetchEngagement(for reelIDs: [ReelID]) {
        guard !reelIDs.isEmpty else { return }
        engagementStore?.prefetch(reelIDs.map { .reel($0) })
    }

    func applyBootstrap(_ snapshot: ProfileState) {
        if snapshot.didBootstrap || snapshot.phase == .loaded {
            isScreenOwned = true
        }
        let beforeCount = items.count
        guard snapshot.didLoadClips || !snapshot.clips.isEmpty else {
            if (snapshot.phase == .loading || snapshot.didBootstrap), items.isEmpty {
                state = .loading
            }
            return
        }

        if hasLoaded {
            guard !snapshot.clips.isEmpty else { return }
            items = OwnerProfileOptimisticStore.merging(overlay: snapshot.clips, into: items)
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
        syncGeneration &+= 1
        let generation = syncGeneration
        loadTask = Task { await performLoad(generation: generation) }
    }

    func refresh() async {
        syncGeneration &+= 1
        let generation = syncGeneration
        loadTask?.cancel()
        await performLoad(generation: generation)
    }

    func loadMoreIfNeeded() async {
        // Web Profile Clips loads the full list in one request.
    }

    func openClip(_ reel: Reel) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(reel)
        navigationCoordinator.open(.profile(.reel(reel.id)))
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
            OwnerProfileOptimisticStore.shared.syncOwnerClipsState(items)
            loadTask = nil
            return
        }

        state = items.isEmpty ? .loading : state
        do {
            // Web `fetchUserProfileReels` — full list + trade-linked visibility filter.
            let result = try await feed.profileReels(for: profileOwnerID)
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
            let serverMerged = OwnerProfileOptimisticStore.merging(overlay: overlay, into: result.reels)
            items = OwnerProfileOptimisticStore.merging(overlay: serverMerged, into: items)
            detailCache.seed(reels: items)
            if !result.embeddedTrades.isEmpty {
                detailCache.seed(trades: result.embeddedTrades)
            }
            hasLoaded = true
            #if DEBUG
            ProfileClipsSync.logFetch(
                userID: profileOwnerID.rawValue,
                count: result.reels.count,
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
            ProfileClipsSync.logAuthoritativeReturned(generation: generation, count: result.reels.count)
            ProfileClipsSync.logReconciled(
                beforeCount: beforeCount,
                snapshotCount: result.reels.count,
                afterCount: items.count
            )
            ProfileClipsSync.logUIVisibleCount(items.count)
            #endif
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
            OwnerProfileOptimisticStore.shared.syncOwnerClipsState(items)
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
                state = .failed(message: ProfileSectionSupport.message(for: error))
            }
        }
        loadTask = nil
    }
}
