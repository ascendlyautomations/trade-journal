import Foundation
import Observation

@Observable
@MainActor
final class ClipsContainerViewModel {
    private(set) var state: ProfileSectionLoadState = .idle
    private(set) var items: [Reel] = []

    private let profileID: ProfileID
    private let feed: any FeedRepository
    private let navigationCoordinator: NavigationCoordinator
    private let detailCache: DetailPresentationCache
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false

    init(
        profileID: ProfileID,
        feed: any FeedRepository,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache
    ) {
        self.profileID = profileID
        self.feed = feed
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
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
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            hasLoaded = true
            items = ProfileClipFixtures.samples(owner: profileID)
            detailCache.seed(reels: items)
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            loadTask = nil
            return
        }

        state = items.isEmpty ? .loading : state
        do {
            // Web `fetchUserProfileReels` — full list + trade-linked visibility filter.
            let reels = try await feed.profileReels(for: profileID)
            guard !Task.isCancelled else { return }
            items = reels
            detailCache.seed(reels: items)
            hasLoaded = true
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        } catch {
            guard !Task.isCancelled else { return }
            if items.isEmpty {
                state = .failed(message: ProfileSectionSupport.message(for: error))
            }
        }
        loadTask = nil
    }
}
