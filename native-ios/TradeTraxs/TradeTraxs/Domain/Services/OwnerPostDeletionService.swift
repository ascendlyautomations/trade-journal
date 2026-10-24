import Foundation

/// Single owner wall-post deletion path — Post Detail and Profile cards.
@MainActor
enum OwnerPostDeletionService {
    static func deleteOwnedPost(
        postID: PostID,
        owner: ProfileID,
        profiles: any ProfileRepository,
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
            try await profiles.deleteWallPost(id: postID)
        }
        detailCache.removePost(id: postID)
        OwnerProfileOptimisticStore.shared.notePostDeleted(id: postID)
    }
}
