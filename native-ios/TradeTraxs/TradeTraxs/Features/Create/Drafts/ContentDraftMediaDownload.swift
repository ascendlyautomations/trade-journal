import Foundation

nonisolated enum ContentDraftMediaDownload {
    static func imageData(
        path: String,
        session: any SessionProviding,
        objectStorage: any ObjectStorageProviding
    ) async throws -> Data {
        guard let userID = await session.currentUserID else {
            throw AppError.authentication(.sessionMissing)
        }
        let prefix = "\(userID.rawValue)/"
        guard path.hasPrefix(prefix), !path.contains("..") else {
            throw AppError.unknown(message: "Couldn't restore draft media.")
        }
        return try await objectStorage.download(bucket: StorageBucket.draftMedia.rawValue, path: path)
    }
}
