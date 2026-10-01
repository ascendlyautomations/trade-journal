import Foundation
import UIKit

nonisolated enum SubmissionScreenshotUpload {
    static let maxImageBytes = 15 * 1024 * 1024

    /// Owner-scoped path: `{userId}/{prefix}/opt/{timestamp}.jpg`.
    /// Screenshots insert policy requires the first folder to be `auth.uid()`.
    static func storageObjectPath(userID: String, prefix: String) -> String {
        let trimmedUser = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        return "\(trimmedUser)/\(trimmedPrefix)/opt/\(timestamp).jpg"
    }

    static func uploadJPEG(
        image: UIImage,
        userID: String,
        prefix: String,
        storage: any SupabaseStorageProviding
    ) async throws -> String {
        let data = await MainActor.run {
            MediaImagePreparation.chatJPEGData(from: image)
        }
        guard let data else {
            throw UserSubmissionError.screenshotUpload("Couldn't prepare that image.")
        }
        guard data.count <= maxImageBytes else {
            throw UserSubmissionError.screenshotUpload("Image must be 15 MB or smaller.")
        }

        let path = storageObjectPath(userID: userID, prefix: prefix)
        _ = try await storage.upload(
            bucket: StorageBucket.screenshots.rawValue,
            path: path,
            data: data,
            contentType: "image/jpeg"
        )
        guard let url = storage.publicURL(bucket: StorageBucket.screenshots.rawValue, path: path) else {
            throw UserSubmissionError.screenshotUpload("Couldn't resolve screenshot URL.")
        }
        return url.absoluteString
    }
}
