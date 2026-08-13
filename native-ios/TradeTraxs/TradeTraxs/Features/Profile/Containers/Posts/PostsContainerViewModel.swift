import Foundation
import Observation

@Observable
@MainActor
final class PostsContainerViewModel {
    private(set) var state: ProfileSectionLoadState = .idle
    private(set) var items: [Post] = []

    private let profileID: ProfileID
    private let profiles: any ProfileRepository
    private let navigationCoordinator: NavigationCoordinator
    private let detailCache: DetailPresentationCache
    private let engagementStore: EngagementStore?
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var isScreenOwned = false

    init(
        profileID: ProfileID,
        profiles: any ProfileRepository,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore? = nil
    ) {
        self.profileID = profileID
        self.profiles = profiles
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        self.engagementStore = engagementStore
    }

    func prefetchEngagement(for postIDs: [PostID]) {
        guard !postIDs.isEmpty else { return }
        engagementStore?.prefetch(postIDs.map { .profilePost($0) })
    }

    func applyBootstrap(_ snapshot: ProfileState) {
        guard snapshot.didBootstrap || snapshot.phase == .loaded || !snapshot.posts.isEmpty else {
            if snapshot.phase == .loading, items.isEmpty { state = .loading }
            return
        }
        isScreenOwned = true
        hasLoaded = true
        items = snapshot.posts
        detailCache.seed(posts: items)
        state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        prefetchEngagement(for: items.map(\.id))
    }

    func loadIfNeeded() {
        if isScreenOwned { return }
        guard !hasLoaded, loadTask == nil else { return }
        loadTask = Task { await performLoad() }
    }

    func refresh() async {
        loadTask?.cancel()
        await performLoad()
    }

    func loadMoreIfNeeded() async {
        // Web Profile Posts loads the full wall in one request.
    }

    func openPost(_ post: Post) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(post)
        navigationCoordinator.open(.profile(.post(post.id)))
    }

    private func performLoad() async {
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            hasLoaded = true
            items = ProfilePostFixtures.samples(owner: profileID)
            detailCache.seed(posts: items)
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
            loadTask = nil
            return
        }

        state = items.isEmpty ? .loading : state
        do {
            // Web: `profile_posts` select * / user_id / created_at desc (+ pinned client sort).
            let page = try await profiles.wallPosts(
                for: profileID,
                page: PageRequest(limit: 500)
            )
            guard !Task.isCancelled else { return }
            items = page.items
            detailCache.seed(posts: items)
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
