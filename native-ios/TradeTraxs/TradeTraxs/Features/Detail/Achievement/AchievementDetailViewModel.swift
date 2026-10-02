import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class AchievementDetailViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var achievement: Achievement?
    private(set) var author: Profile?
    private(set) var authorAvatar: Image?
    private(set) var isOwner = false
    private(set) var isDeleting = false
    private(set) var deleteErrorMessage: String?

    let achievementID: AchievementID

    private let achievements: any AchievementRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let imagePipeline: any ImagePipeline
    private let cache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private var loadTask: Task<Void, Never>?

    init(
        achievementID: AchievementID,
        achievements: any AchievementRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        imagePipeline: any ImagePipeline,
        cache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.achievementID = achievementID
        self.achievements = achievements
        self.profiles = profiles
        self.session = session
        self.imagePipeline = imagePipeline
        self.cache = cache
        self.navigationCoordinator = navigationCoordinator
    }

    var authorDisplayName: String { DetailAuthorPresentation.displayName(for: author) }
    var authorUsername: String { DetailAuthorPresentation.username(for: author) }
    var authorInitials: String { DetailAuthorPresentation.initials(for: author) }

    func loadIfNeeded() {
        guard loadTask == nil, phase != .loaded || achievement == nil else { return }
        loadTask = Task { await performLoad() }
    }

    func refresh() async {
        loadTask?.cancel()
        await performLoad(forceNetwork: true)
    }

    func clearDeleteError() {
        deleteErrorMessage = nil
    }

    func deleteAchievement() async -> Bool {
        guard isOwner, !isDeleting, let achievement else { return false }
        isDeleting = true
        deleteErrorMessage = nil
        defer { isDeleting = false }
        do {
            try await OwnerAchievementDeletionService.deleteOwnedAchievement(
                achievementID: achievement.id,
                owner: achievement.ownerProfileID,
                previous: achievement,
                achievements: achievements,
                session: session,
                detailCache: cache
            )
            ExperienceHaptics.play(.success)
            navigationCoordinator.pop()
            return true
        } catch {
            deleteErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
            return false
        }
    }

    private func performLoad(forceNetwork: Bool = false) async {
        if !forceNetwork, let seed = cache.achievement(id: achievementID) {
            achievement = seed
            phase = .loaded
            await loadAuthor(for: seed.ownerProfileID)
            loadTask = nil
            return
        }

        if achievementID.rawValue.hasPrefix("dev-") {
            let owner = ProfileID(
                await session.currentUserID?.rawValue ?? "dev.screenshot"
            )
            if let fixture = ProfileAchievementFixtures.samples(owner: owner)
                .first(where: { $0.id == achievementID })
            {
                cache.seed(fixture)
                achievement = fixture
                phase = .loaded
                await loadAuthor(for: fixture.ownerProfileID)
                loadTask = nil
                return
            }
        }

        if achievement == nil {
            phase = .loading
        }

        do {
            let loaded = try await achievements.achievement(id: achievementID)
            guard !Task.isCancelled else { return }
            cache.seed(loaded)
            achievement = loaded
            phase = .loaded
            await loadAuthor(for: loaded.ownerProfileID)
        } catch {
            guard !Task.isCancelled else { return }
            if achievement == nil {
                phase = .failed(ProfileSectionSupport.message(for: error))
            }
        }
        loadTask = nil
    }

    private func loadAuthor(for profileID: ProfileID) async {
        let userID = await session.currentUserID
        isOwner = userID?.rawValue == profileID.rawValue
        if let cached = cache.profile(id: profileID) {
            author = cached
        } else {
            author = try? await SessionProfileStore.shared.profiles(
                ids: [profileID],
                detailCache: cache,
                repository: profiles
            ).first
        }
        authorAvatar = await DetailAuthorPresentation.loadAvatar(
            for: author,
            imagePipeline: imagePipeline
        )
    }
}
