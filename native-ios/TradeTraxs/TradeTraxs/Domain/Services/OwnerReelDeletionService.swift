import Foundation

/// Single owner clip deletion path — Clip Detail and Profile grid.
@MainActor
enum OwnerReelDeletionService {
    static func deleteOwnedReel(
        reelID: ReelID,
        owner: ProfileID,
        feed: any FeedRepository,
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
            try await feed.deleteReel(id: reelID)
        }
        detailCache.removeReel(id: reelID)
        OwnerProfileOptimisticStore.shared.noteReelDeleted(id: reelID)
    }
}
