import Foundation

/// Upload + insert path matching web `lib/publishStory.ts`.
enum StoryPublishPipeline {
    private static let maxStoryVideoBytes = 15 * 1024 * 1024
    static func publish(
        imageData: Data,
        contentType: String,
        originalFileName: String,
        authorID: ProfileID,
        feed: any FeedRepository,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        predeterminedStoragePath: String? = nil,
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

        let storagePath: String
        if let predetermined = predeterminedStoragePath, !predetermined.isEmpty {
            storagePath = predetermined
        } else {
            storagePath = StorageOptimizedMedia.objectPath(prefix: authorID.rawValue, fileExtension: "jpg")
        }

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

    static func publishVideo(
        fileURL: URL,
        contentType: String,
        originalFileName: String,
        authorID: ProfileID,
        feed: any FeedRepository,
        uploadService: any UploadService,
        objectStorage: any ObjectStorageProviding,
        predeterminedStoragePath: String? = nil,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> Story {
        onProgress?(0.08)
        _ = try await StoryMediaDuration.validatedDurationSeconds(at: fileURL)

        let uploadData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard !uploadData.isEmpty else {
            throw AppError.unknown(message: "Couldn't read this video.")
        }
        guard uploadData.count <= maxStoryVideoBytes else {
            throw AppError.unknown(message: "Video must be 15 MB or smaller.")
        }

        let storagePath: String
        if let predetermined = predeterminedStoragePath, !predetermined.isEmpty {
            storagePath = predetermined
        } else {
            storagePath = StorageOptimizedMedia.objectPath(prefix: authorID.rawValue, fileExtension: "mp4")
        }

        onProgress?(0.15)
        let uploaded = try await uploadService.upload(
            UploadRequest(
                bucket: StorageBucket.stories.rawValue,
                path: storagePath,
                data: uploadData,
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

    static func makeJobStoragePath(
        jobID: String,
        authorID: ProfileID,
        originalFileName: String,
        contentType: String
    ) -> String {
        let ext = contentType.lowercased().hasPrefix("video/") ? "mp4" : "jpg"
        return StorageOptimizedMedia.objectPath(prefix: authorID.rawValue, fileExtension: ext)
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
