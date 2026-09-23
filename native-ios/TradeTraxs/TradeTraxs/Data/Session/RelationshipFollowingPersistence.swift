import Foundation

/// Viewer-scoped **complete** following-set disk snapshot (`SessionDiskCache.following`).
nonisolated enum RelationshipFollowingPersistence {
    static let schemaVersion = 1
    static let reconciliationMaxAge: TimeInterval = 6 * 60 * 60

    static func saveComplete(ids: [String], viewerID: ProfileID, generation: UInt64) {
        guard !RelationshipWriteGeneration.isStale(viewerID: viewerID, generation: generation) else {
            return
        }
        SessionDiskCache.saveCompleteFollowing(ids: ids, for: viewerID)
    }

    static func loadComplete(for viewerID: ProfileID) -> [String]? {
        SessionDiskCache.loadCompleteFollowing(
            for: viewerID,
            maxAge: reconciliationMaxAge
        )
    }
}
