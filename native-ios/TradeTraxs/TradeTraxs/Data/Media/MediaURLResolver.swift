import Foundation

/// Resolves ``MediaReference`` identifiers to playable / displayable URLs.
nonisolated enum MediaURLResolver {
    static func url(
        for reference: MediaReference,
        bucket: StorageBucket,
        storage: any ObjectStorageProviding
    ) -> URL? {
        let identifier = reference.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return nil }

        if let url = URL(string: identifier),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }

        // Stories bucket is private: raw object paths must use signed URLs or authenticated download.
        if bucket == .stories {
            StoryDebug.log(
                "mediaURL.storiesPrivatePath",
                "path=\(identifier)"
            )
            return nil
        }

        return storage.publicURL(bucket: bucket.rawValue, path: identifier)
    }
}
