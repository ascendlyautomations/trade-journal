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
        predeterminedStoragePath: String? = nil,
        onProgress: ((Double) -> Void)? = nil,
        onPrepared: ((_ publicURL: String, _ storagePath: String) -> Void)? = nil
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
        onPrepared?(publicURL, uploaded.id)
        let story = try await feed.createStory(
            userID: authorID,
            imageURL: publicURL
        )
        onProgress?(1)
        return story
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
        textOverlays: [StoryTextOverlayRecord] = [],
        onProgress: ((Double) -> Void)? = nil,
        onPrepared: ((_ publicURL: String, _ storagePath: String) -> Void)? = nil
    ) async throws -> Story {
        onProgress?(0.08)
        _ = try await StoryMediaDuration.validatedDurationSeconds(at: fileURL)

        let prepared = try await StoryVideoPreparation.prepareForUpload(
            from: fileURL,
            contentType: contentType
        ) { value in
            onProgress?(0.08 + value * 0.55)
        }
        defer {
            if prepared.fileURL != fileURL {
                MediaVideoPreparation.cleanupTemporaryFile(at: prepared.fileURL)
            }
        }

        guard prepared.byteCount > 0 else {
            throw AppError.unknown(message: "Couldn't read this video.")
        }
        _ = try await StoryMediaDuration.validatedDurationSeconds(at: prepared.fileURL)

        let storagePath: String
        if let predetermined = predeterminedStoragePath, !predetermined.isEmpty {
            storagePath = predetermined
        } else {
            storagePath = StorageOptimizedMedia.objectPath(prefix: authorID.rawValue, fileExtension: "mp4")
        }

        onProgress?(0.68)
        let uploaded = try await uploadService.uploadFile(
            UploadFileRequest(
                bucket: StorageBucket.stories.rawValue,
                path: storagePath,
                fileURL: prepared.fileURL,
                contentType: prepared.contentType,
                purpose: nil
            )
        )
        onProgress?(0.78)

        let publicURL = objectStorage.publicURL(
            bucket: StorageBucket.stories.rawValue,
            path: uploaded.id
        )?.absoluteString ?? uploaded.id

        onProgress?(0.85)
        onPrepared?(publicURL, uploaded.id)
        let story = try await feed.createStory(
            userID: authorID,
            imageURL: publicURL,
            textOverlays: textOverlays
        )
        onProgress?(1)
        return story
    }

    enum ExistingStoryLookup {
        case found(Story)
        case absent
        case unavailable(Error)
    }

    /// Matches a story already stored for this upload. A failed lookup is not treated as absence.
    static func lookupExistingStory(
        imageURL: String,
        authorID: ProfileID,
        feed: any FeedRepository
    ) async -> ExistingStoryLookup {
        do {
            let stories = try await feed.allActiveStories(for: authorID)
            if let match = stories.first(where: { story in
                story.authorProfileID == authorID && story.media.id == imageURL
            }) {
                return .found(match)
            }
            return .absent
        } catch {
            return .unavailable(error)
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
