import Foundation

/// Upload + insert path matching web `lib/publishStory.ts`.
enum StoryPublishPipeline {
    static func publish(
        imageData: Data,
        contentType: String,
        originalFileName: String,
        authorID: ProfileID,
        feed: any FeedRepository,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> Story {
        onProgress?(0.08)

        if let message = StoryUploadValidation.validate(
            data: imageData,
            contentType: contentType,
            fileName: originalFileName
        ) {
            throw AppError.unknown(message: message)
        }

        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let safeName = sanitizedFileName(originalFileName, contentType: contentType)
        let storagePath = "\(authorID.rawValue)/\(stamp)-\(safeName)"

        onProgress?(0.15)
        let uploaded = try await uploadService.upload(
            UploadRequest(
                bucket: StorageBucket.stories.rawValue,
                path: storagePath,
                data: imageData,
                contentType: contentType,
                purpose: nil
            )
        )
        onProgress?(0.78)

        let publicURL = objectStorage.publicURL(
            bucket: StorageBucket.stories.rawValue,
            path: uploaded.id
        )?.absoluteString ?? uploaded.id

        onProgress?(0.85)
        do {
            let story = try await feed.createStory(
                userID: authorID,
                imageURL: publicURL
            )
            onProgress?(1)
            return story
        } catch {
            try? await objectStorage.delete(
                bucket: StorageBucket.stories.rawValue,
                path: uploaded.id
            )
            throw error
        }
    }

    private static func sanitizedFileName(_ name: String, contentType: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let base = (trimmed as NSString).lastPathComponent
            if base.contains(".") {
                return base.replacingOccurrences(of: " ", with: "_")
            }
        }
        switch contentType.lowercased() {
        case "image/png": return "story.png"
        case "image/webp": return "story.webp"
        case "image/gif": return "story.gif"
        default: return "story.jpg"
        }
    }
}
