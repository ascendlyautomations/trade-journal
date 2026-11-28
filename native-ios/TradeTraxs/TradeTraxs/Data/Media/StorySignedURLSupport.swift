import Foundation

/// Normalizes private story signed URLs from Supabase Storage (`/object/sign/stories/...`).
nonisolated enum StorySignedURLSupport {
    private static let signMarkers = [
        "/storage/v1/object/sign/stories/",
        "/object/sign/stories/",
    ]

    static func containsSignedMarker(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return signMarkers.contains { lower.contains($0) }
    }

    private static func signMarkerRange(in lower: String) -> Range<String.Index>? {
        for marker in signMarkers {
            if let range = lower.range(of: marker) {
                return range
            }
        }
        return nil
    }

    /// Object path inside the `stories` bucket (`uuid/opt/file.jpg`), never a sign URL fragment.
    static func objectPath(fromSignedOrRelative raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        guard let range = signMarkerRange(in: lower) else { return nil }
        let offset = lower.distance(from: lower.startIndex, to: range.upperBound)
        let start = trimmed.index(trimmed.startIndex, offsetBy: offset)
        let tail = String(trimmed[start...])
        let path = tail.split(separator: "#").first.map(String.init)?.split(separator: "?").first.map(String.init) ?? ""
        guard !path.isEmpty, !path.contains(".."), !path.hasPrefix("/") else { return nil }
        return path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Absolute signed playback URL; preserves the `token` query. Handles legacy relative cache values.
    static func normalizedSignedURL(_ raw: String, projectBase: URL?) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, containsSignedMarker(trimmed) else { return nil }
        return absoluteSignedURL(trimmed, projectBase: projectBase)
    }

    /// `projectBase + "/storage/v1" + signedURL` when Supabase returns `/object/sign/stories/...`.
    static func absoluteSignedURL(_ raw: String, projectBase: URL?) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.lowercased().hasPrefix("http"), let absolute = URL(string: trimmed) {
            let fixed = signedURLWithStorageV1Prefix(absolute)
            return preserveQuery(from: trimmed, into: fixed)
        }

        guard let base = projectBase else {
            return URL(string: storageRelativeSignedPath(trimmed))
        }
        var root = base.absoluteString
        while root.hasSuffix("/") { root.removeLast() }
        let path = storageRelativeSignedPath(trimmed)
        guard let absolute = URL(string: "\(root)\(path)") else { return nil }
        return preserveQuery(from: trimmed, into: absolute)
    }

    static func normalizedSignedURL(_ url: URL, projectBase: URL?) -> URL {
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            let fixed = signedURLWithStorageV1Prefix(url)
            return preserveQuery(from: url.absoluteString, into: fixed)
        }
        return absoluteSignedURL(url.absoluteString, projectBase: projectBase) ?? url
    }

    /// Ensures `/storage/v1` precedes `/object/sign/...` without duplicating an existing prefix.
    private static func storageRelativeSignedPath(_ raw: String) -> String {
        let path = raw.hasPrefix("/") ? raw : "/\(raw)"
        let lower = path.lowercased()
        if lower.hasPrefix("/storage/v1/") {
            return path
        }
        if lower.hasPrefix("/object/sign/") {
            return "/storage/v1\(path)"
        }
        return path
    }

    private static func signedURLWithStorageV1Prefix(_ url: URL) -> URL {
        let path = url.path
        let lower = path.lowercased()
        guard lower.contains("/object/sign/"), !lower.hasPrefix("/storage/v1/") else {
            return url
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.path = "/storage/v1" + path
        return components.url ?? url
    }

    /// Strips bucket prefix if the sign API path was accidentally prefixed with `stories/`.
    static func sanitizedObjectPathForSignAPI(_ raw: String, bucket: String) -> String {
        var cleaned = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
        if bucket == StorageBucket.stories.rawValue, cleaned.hasPrefix("stories/") {
            cleaned = String(cleaned.dropFirst("stories/".count))
        }
        if containsSignedMarker(cleaned), let extracted = objectPath(fromSignedOrRelative: cleaned) {
            return extracted
        }
        return cleaned
    }

    static func redactForLog(_ raw: String) -> String {
        guard let tokenRange = raw.range(of: "token=", options: .caseInsensitive) else {
            return raw
        }
        let suffix = raw[tokenRange.upperBound...]
        if let amp = suffix.firstIndex(of: "&") {
            return String(raw[..<tokenRange.upperBound]) + "<redacted>" + suffix[amp...]
        }
        return String(raw[..<tokenRange.upperBound]) + "<redacted>"
    }

    private static func preserveQuery(from raw: String, into url: URL) -> URL {
        guard raw.contains("?"), let rawURL = URL(string: raw), let query = rawURL.query else {
            return url
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        if components.query == nil || components.query?.isEmpty == true {
            components.query = query
            return components.url ?? url
        }
        return url
    }
}