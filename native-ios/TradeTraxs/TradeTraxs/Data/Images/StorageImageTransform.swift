import Foundation

/// Supabase Storage image transforms — parity with web `lib/optimizedStorageImage.ts`.
///
/// Converts `/storage/v1/object/public/{bucket}/path` into
/// `/storage/v1/render/image/public/{bucket}/path?width=&quality=&resize=`.
nonisolated enum StorageImageTransform {
    enum Preset: Sendable {
        case avatar
        case feedThumb
        case feedDetail
        case story
        case reelThumb
    }

    private static let objectPublic = "/storage/v1/object/public/"
    private static let renderPublic = "/storage/v1/render/image/public/"

    static func isSupabaseStoragePublicURL(_ url: URL) -> Bool {
        let path = url.path
        return path.contains(objectPublic) || path.contains(renderPublic)
    }

    /// Stable identity for logging — host + path without query tokens.
    static func urlIdentity(for url: URL) -> String {
        var components = URLComponents()
        components.host = url.host
        components.path = url.path
        return (components.string ?? url.absoluteString).lowercased()
    }

    static func optimizedURL(for url: URL, preset: Preset) -> URL {
        guard isSupabaseStoragePublicURL(url) else { return url }

        let renderBase: String
        if url.path.contains(renderPublic) {
            renderBase = url.absoluteString.split(separator: "?").first.map(String.init) ?? url.absoluteString
        } else {
            renderBase = url.absoluteString.replacingOccurrences(
                of: objectPublic,
                with: renderPublic
            ).split(separator: "?").first.map(String.init)
                ?? url.absoluteString
        }

        var query = URLComponents(string: renderBase)?.queryItems ?? []
        query.removeAll()
        switch preset {
        case .avatar:
            query = [
                URLQueryItem(name: "width", value: "96"),
                URLQueryItem(name: "height", value: "96"),
                URLQueryItem(name: "quality", value: "80"),
                URLQueryItem(name: "resize", value: "cover"),
            ]
        case .feedThumb:
            query = [
                URLQueryItem(name: "width", value: "640"),
                URLQueryItem(name: "quality", value: "75"),
            ]
        case .feedDetail:
            query = [
                URLQueryItem(name: "width", value: "1280"),
                URLQueryItem(name: "quality", value: "82"),
            ]
        case .story:
            query = [
                URLQueryItem(name: "width", value: "1080"),
                URLQueryItem(name: "quality", value: "80"),
                URLQueryItem(name: "resize", value: "contain"),
            ]
        case .reelThumb:
            query = [
                URLQueryItem(name: "width", value: "560"),
                URLQueryItem(name: "height", value: "996"),
                URLQueryItem(name: "quality", value: "75"),
                URLQueryItem(name: "resize", value: "cover"),
            ]
        }

        var components = URLComponents(string: renderBase)
        components?.queryItems = query
        return components?.url ?? url
    }

    static func preset(for purpose: ImagePurpose, delivery: ImageDeliveryQuality) -> Preset? {
        guard delivery == .feedDisplay else { return nil }
        switch purpose {
        case .profileAvatar: return .avatar
        case .tradeScreenshot, .postImage: return .feedThumb
        case .storyMedia: return .story
        case .reelThumbnail: return .reelThumb
        }
    }
}
