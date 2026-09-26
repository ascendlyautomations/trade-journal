import CryptoKit
import Foundation

/// Stable cache identity for immutable public Supabase reel MP4 URLs.
nonisolated enum ClipVideoCacheIdentity {
    /// Canonical string for dedupe — host + path, no query/fragment (matches ``Reel/playbackURLIdentity``).
    nonisolated static func canonicalIdentity(for url: URL) -> String {
        var components = URLComponents()
        components.host = url.host?.lowercased()
        components.path = url.path
        if components.path.isEmpty, !url.path.isEmpty {
            components.path = url.path
        }
        let raw = (components.string ?? url.absoluteString).trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return url.absoluteString
        }
        return raw.lowercased()
    }

    nonisolated static func cacheKey(for url: URL) -> String {
        let identity = canonicalIdentity(for: url)
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func cacheKey(for reel: Reel, resolvedURL: URL) -> String {
        _ = reel
        return cacheKey(for: resolvedURL)
    }
}
