import Foundation
import Observation

@Observable
@MainActor
final class AchievementsContainerViewModel {
    private(set) var state: ProfileSectionLoadState = .idle
    private(set) var items: [Achievement] = []

    private let profileID: ProfileID
    private let achievements: any AchievementRepository
    private let navigationCoordinator: NavigationCoordinator
    private let detailCache: DetailPresentationCache
    private let engagementStore: EngagementStore?
    private let viewerIsOwner: Bool
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var isScreenOwned = false

    init(
        profileID: ProfileID,
        achievements: any AchievementRepository,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore? = nil,
        viewerIsOwner: Bool = true
    ) {
        self.profileID = profileID
        self.achievements = achievements
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        self.engagementStore = engagementStore
        self.viewerIsOwner = viewerIsOwner
    }

    func prefetchEngagement(for achievementIDs: [AchievementID]) {
        guard !achievementIDs.isEmpty else { return }
        engagementStore?.prefetch(achievementIDs.map { .achievement($0) })
    }

    func applyBootstrap(_ snapshot: ProfileState) {
        guard snapshot.didBootstrap || snapshot.phase == .loaded || !snapshot.achievements.isEmpty else {
            if snapshot.phase == .loading, items.isEmpty { state = .loading }
            return
        }
        isScreenOwned = true
        hasLoaded = true
        items = snapshot.achievements
        detailCache.seed(achievements: items)
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
        // Web Profile Achievements loads the full ordered list in one request.
    }

    func openAchievement(_ achievement: Achievement) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(achievement)
        navigationCoordinator.open(.profile(.achievement(achievement.id)))
    }

    private func performLoad() async {
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            hasLoaded = true
            items = ProfileAchievementFixtures.samples(owner: profileID)
            detailCache.seed(achievements: items)
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
            loadTask = nil
            return
        }

        state = items.isEmpty ? .loading : state
        do {
            let page = try await achievements.achievements(
                for: profileID,
                page: PageRequest(limit: 500),
                publicOnly: !viewerIsOwner
            )
            guard !Task.isCancelled else { return }
            items = page.items
            detailCache.seed(achievements: items)
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
