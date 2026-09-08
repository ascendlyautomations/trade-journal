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
        guard snapshot.didLoadClips || !snapshot.clips.isEmpty else {
            if (snapshot.phase == .loading || snapshot.didBootstrap), items.isEmpty {
                state = .loading
            }
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
        detailCache.seed(reels: items)
        state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        prefetchEngagement(for: items.map(\.id))
    }

    func loadIfNeeded() {
        guard !hasLoaded, loadTask == nil else { return }
        loadTask = Task { await performLoad() }
    }

    func refresh() async {
        loadTask?.cancel()
        await performLoad()
    }

    func loadMoreIfNeeded() async {
        // Web Profile Clips loads the full list in one request.
    }

    func openClip(_ reel: Reel) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(reel)
        navigationCoordinator.open(.profile(.reel(reel.id)))
    }

    private func performLoad() async {
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileOwnerID) {
            hasLoaded = true
            items = ProfileClipFixtures.samples(owner: profileOwnerID)
            detailCache.seed(reels: items)
            detailCache.seed(trades: ProfileClipFixtures.linkedTrades(for: items))
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
            loadTask = nil
            return
        }

        state = items.isEmpty ? .loading : state
        do {
            // Web `fetchUserProfileReels` — full list + trade-linked visibility filter.
            let result = try await feed.profileReels(for: profileOwnerID)
            guard !Task.isCancelled else { return }
            let overlay = OwnerProfileOptimisticStore.shared.reels.filter {
                $0.authorProfileID == profileOwnerID
                    && OwnerProfileOptimisticStore.isListedOnOwnerProfile($0)
            }
            items = OwnerProfileOptimisticStore.merging(overlay: overlay, into: result.reels)
            detailCache.seed(reels: items)
            if !result.embeddedTrades.isEmpty {
                detailCache.seed(trades: result.embeddedTrades)
            }
            hasLoaded = true
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
        } catch {
            guard !Task.isCancelled else { return }
            if items.isEmpty {
                state = .failed(message: ProfileSectionSupport.message(for: error))
            }
        }
        loadTask = nil
    }
}
