import Foundation

#if DEBUG
nonisolated enum MediaLoadDiagnostics {
    enum Source: String {
        case feedInline
        case clipsPager
        case clipsPrefetch
        case feedImage
        case clipPoster
        case story
        case profile
        case other
    }

    enum Role: String {
        case active
        case prefetch
        case poster
        case image
    }

    static func log(
        contentType: String,
        mediaID: String,
        source: Source,
        role: Role,
        urlIdentity: String? = nil,
        byteCount: Int? = nil,
        cacheHit: Bool? = nil,
        playerCreated: Bool? = nil,
        playerReused: Bool? = nil
    ) {
        var parts = [
            "[MEDIA_LOAD]",
            "type=\(contentType)",
            "id=\(mediaID)",
            "source=\(source.rawValue)",
            "role=\(role.rawValue)",
        ]
        if let urlIdentity, !urlIdentity.isEmpty {
            parts.append("urlHash=\(urlIdentity.hashValue)")
        }
        if let byteCount {
            parts.append("bytes=\(byteCount)")
        }
        if let cacheHit {
            parts.append("cacheHit=\(cacheHit)")
        }
        if let playerCreated {
            parts.append("playerCreated=\(playerCreated)")
        }
        if let playerReused {
            parts.append("playerReused=\(playerReused)")
        }
        print(parts.joined(separator: " "))
    }
}
#else
nonisolated enum MediaLoadDiagnostics {
    enum Source: String { case feedInline, clipsPager, clipsPrefetch, feedImage, clipPoster, story, profile, other }
    enum Role: String { case active, prefetch, poster, image }

    static func log(
        contentType: String,
        mediaID: String,
        source: Source,
        role: Role,
        urlIdentity: String? = nil,
        byteCount: Int? = nil,
        cacheHit: Bool? = nil,
        playerCreated: Bool? = nil,
        playerReused: Bool? = nil
    ) {}
}
#endif
