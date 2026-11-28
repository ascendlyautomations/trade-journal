import Foundation

nonisolated enum StoryStoragePathSupport {
    private static let publicMarker = "/storage/v1/object/public/stories/"

    static func resolve(storagePath: String?, imageURL: String?) -> String? {
        let direct = storagePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !direct.isEmpty {
            if StorySignedURLSupport.containsSignedMarker(direct),
               let path = StorySignedURLSupport.objectPath(fromSignedOrRelative: direct)
            {
                return path
            }
            if !direct.lowercased().hasPrefix("http") {
                return direct.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        }
        return resolve(fromImageURL: imageURL)
    }

    static func resolve(fromImageURL raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if StorySignedURLSupport.containsSignedMarker(trimmed),
           let path = StorySignedURLSupport.objectPath(fromSignedOrRelative: trimmed)
        {
            return path
        }
        if !trimmed.lowercased().hasPrefix("http") {
            return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        guard let range = trimmed.range(of: publicMarker) else { return nil }
        let tail = String(trimmed[range.upperBound...]).split(separator: "?").first.map(String.init) ?? ""
        guard !tail.isEmpty, !tail.contains(".."), !tail.hasPrefix("/") else { return nil }
        return tail
    }
}