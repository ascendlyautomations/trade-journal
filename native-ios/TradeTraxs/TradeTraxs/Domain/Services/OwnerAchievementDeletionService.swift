import Foundation

/// Single owner achievement deletion path — Achievement Detail and Profile cards.
@MainActor
enum OwnerAchievementDeletionService {
    static func deleteOwnedAchievement(
        achievementID: AchievementID,
        owner: ProfileID,
        previous: Achievement?,
        achievements: any AchievementRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache
    ) async throws {
        guard let viewer = await session.currentUserID else {
            throw AppError.domain(.permission(.notAuthenticated))
        }
        guard ProfileID(viewer.rawValue) == owner else {
            throw AppError.domain(.permission(.notOwner))
        }
        if !viewer.rawValue.hasPrefix("dev.") {
            try await achievements.delete(id: achievementID)
        }
        detailCache.removeAchievement(id: achievementID)
        OwnerProfileOptimisticStore.shared.noteAchievementDeleted(
            id: achievementID,
            owner: owner,
            previous: previous
        )
    }
}
