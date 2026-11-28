import Foundation

/// Signed URL cache for private `stories` bucket playback.
actor StorySignedMediaResolver {
    static let shared = StorySignedMediaResolver()

    private var storage: (any ObjectStorageProviding)?
    private var projectBaseURL: URL?
    private var cache: [String: (url: URL, expiresAt: Date)] = [:]
    private let defaultTTL: TimeInterval = 3300

    func configure(storage: any ObjectStorageProviding, projectBaseURL: URL? = nil) {
        self.storage = storage
        self.projectBaseURL = projectBaseURL
    }

    func playableURL(
        storagePath: String?,
        imageURL: String?,
        bucket: StorageBucket = .stories
    ) async -> URL? {
        let combined = imageURL ?? storagePath
        if let combined,
           StorySignedURLSupport.containsSignedMarker(combined),
           let normalized = StorySignedURLSupport.normalizedSignedURL(combined, projectBase: projectBaseURL)
        {
            if let objectPath = StorySignedURLSupport.objectPath(fromSignedOrRelative: combined) {
                store(normalized, forKey: objectPath)
            }
            StoryDebug.log(
                "signedMedia.existingSigned",
                "url=\(StorySignedURLSupport.redactForLog(normalized.absoluteString))"
            )
            return normalized
        }

        guard let objectPath = StoryStoragePathSupport.resolve(storagePath: storagePath, imageURL: imageURL) else {
            let legacy = legacyAbsoluteURL(imageURL)
            StoryDebug.log(
                "signedMedia.unresolvedPath",
                "storagePath=\(StorySignedURLSupport.redactForLog(storagePath ?? "nil")) imageURL=\(StorySignedURLSupport.redactForLog(imageURL ?? "nil")) legacy=\(legacy != nil)"
            )
            return legacy
        }

        if let cached = cachedURL(for: objectPath) {
            StoryDebug.log(
                "signedMedia.cacheHit",
                "path=\(objectPath) url=\(StorySignedURLSupport.redactForLog(cached.absoluteString))"
            )
            return cached
        }

        guard let storage else {
            let legacy = legacyAbsoluteURL(imageURL)
            StoryDebug.log(
                "signedMedia.noStorage",
                "path=\(objectPath) legacy=\(legacy != nil)"
            )
            return legacy
        }

        do {
            let signed = try await storage.signedURL(
                bucket: bucket.rawValue,
                path: objectPath,
                expiresIn: Int(defaultTTL)
            )
            let normalized = StorySignedURLSupport.normalizedSignedURL(signed, projectBase: projectBaseURL)
            store(normalized, forKey: objectPath)
            StoryDebug.log(
                "signedMedia.ok",
                "bucket=\(bucket.rawValue) path=\(objectPath) url=\(StorySignedURLSupport.redactForLog(normalized.absoluteString))"
            )
            return normalized
        } catch {
            StoryDebug.log(
                "signedMedia.error",
                "bucket=\(bucket.rawValue) path=\(objectPath) error=\(error.localizedDescription)"
            )
            return legacyAbsoluteURL(imageURL)
        }
    }

    /// Signed playback reference for private `stories` bucket (web `createStorySignedMediaUrl` parity).
    func resolvedPlaybackReference(_ reference: MediaReference) async -> MediaReference {
        if StorySignedURLSupport.containsSignedMarker(reference.id),
           let url = await playableURL(storagePath: nil, imageURL: reference.id)
        {
            return MediaReference(
                id: url.absoluteString,
                kind: reference.kind,
                altText: reference.altText
            )
        }
        let path = StoryStoragePathSupport.resolve(storagePath: nil, imageURL: reference.id)
        let isVideo = reference.kind == .video
        if let signed = await signedMediaReference(
            storagePath: path,
            imageURL: reference.id,
            isVideo: isVideo
        ) {
            return signed
        }
        if let path, !path.isEmpty {
            return MediaReference(id: path, kind: reference.kind, altText: reference.altText)
        }
        return reference
    }

    func signedMediaReference(
        storagePath: String?,
        imageURL: String?,
        isVideo: Bool
    ) async -> MediaReference? {
        guard let url = await playableURL(storagePath: storagePath, imageURL: imageURL) else {
            StoryDebug.log(
                "signedMedia.referenceNil",
                "isVideo=\(isVideo) storagePath=\(StorySignedURLSupport.redactForLog(storagePath ?? "nil")) imageURL=\(StorySignedURLSupport.redactForLog(imageURL ?? "nil"))"
            )
            return nil
        }
        return MediaReference(
            id: url.absoluteString,
            kind: isVideo ? .video : .image,
            altText: nil
        )
    }

    private func legacyAbsoluteURL(_ raw: String?) -> URL? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.lowercased().hasPrefix("http") else { return nil }
        return StorySignedURLSupport.normalizedSignedURL(trimmed, projectBase: projectBaseURL)
            ?? URL(string: trimmed)
    }

    private func cachedURL(for objectPath: String) -> URL? {
        let key = objectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let entry = cache[key], entry.expiresAt > Date() else {
            return nil
        }
        return StorySignedURLSupport.normalizedSignedURL(entry.url, projectBase: projectBaseURL)
    }

    private func store(_ url: URL, forKey objectPath: String) {
        let normalized = StorySignedURLSupport.normalizedSignedURL(url, projectBase: projectBaseURL)
        let key = objectPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        cache[key] = (normalized, Date().addingTimeInterval(defaultTTL))
    }
}