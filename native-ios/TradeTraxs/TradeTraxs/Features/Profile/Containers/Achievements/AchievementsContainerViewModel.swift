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
    private let viewerIsOwner: Bool
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false

    init(
        profileID: ProfileID,
        achievements: any AchievementRepository,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache,
        viewerIsOwner: Bool = true
    ) {
        self.profileID = profileID
        self.achievements = achievements
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        self.viewerIsOwner = viewerIsOwner
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
        } catch {
            guard !Task.isCancelled else { return }
            if items.isEmpty {
                state = .failed(message: ProfileSectionSupport.message(for: error))
            }
        }
        loadTask = nil
    }
}
