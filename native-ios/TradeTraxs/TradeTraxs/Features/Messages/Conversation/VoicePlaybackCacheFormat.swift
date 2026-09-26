import Foundation

/// Maps remote voice URLs / HTTP metadata / file bytes to a safe on-disk cache extension.
nonisolated enum VoicePlaybackCacheFormat {
    nonisolated static let supportedURLExtensions: Set<String> = ["wav", "m4a", "aac", "mp4", "caf"]

    nonisolated static func remoteExtension(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        guard supportedURLExtensions.contains(ext) else { return nil }
        return ext
    }

    nonisolated static func extensionFromContentType(_ contentType: String?) -> String? {
        guard let contentType else { return nil }
        let raw = contentType
            .split(separator: ";", maxSplits: 1)
            .first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard let raw, !raw.isEmpty else { return nil }
        switch raw {
        case "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave":
            return "wav"
        case "audio/mp4", "audio/x-m4a", "audio/m4a":
            return "m4a"
        case "audio/aac", "audio/x-aac":
            return "aac"
        case "audio/mp4a-latm":
            return "m4a"
        case "audio/x-caf", "audio/caf":
            return "caf"
        default:
            return nil
        }
    }

    nonisolated static func extensionFromDataPrefix(_ data: Data) -> String? {
        guard data.count >= 12 else { return nil }
        if data.starts(with: Data("RIFF".utf8)),
           data.subdata(in: 8 ..< 12) == Data("WAVE".utf8)
        {
            return "wav"
        }
        if data.count >= 8, data.subdata(in: 4 ..< 8) == Data("ftyp".utf8) {
            return "m4a"
        }
        if data.starts(with: Data("caff".utf8)) {
            return "caf"
        }
        return nil
    }

    /// Authoritative cache extension for a download (URL → bytes → Content-Type).
    nonisolated static func resolveCacheExtension(
        remoteURL: URL,
        responseContentType: String?,
        downloadedData: Data
    ) -> (resolvedContainer: String, cacheExtension: String) {
        if let remote = remoteExtension(from: remoteURL) {
            return (remote, remote)
        }
        if let fromBytes = extensionFromDataPrefix(downloadedData) {
            return (fromBytes, fromBytes)
        }
        if let fromType = extensionFromContentType(responseContentType) {
            return (fromType, fromType)
        }
        return ("m4a", "m4a")
    }

    nonisolated static func legacyForcedM4APath(hash: String, directory: URL) -> URL {
        directory.appendingPathComponent("\(hash).m4a")
    }

    nonisolated static func cachePath(hash: String, cacheExtension: String, directory: URL) -> URL {
        directory.appendingPathComponent("\(hash).\(cacheExtension)")
    }

    /// When the remote URL declares WAV, never reuse the pre-fix forced `.m4a` cache file.
    nonisolated static func shouldIgnoreLegacyM4ACache(remoteURL: URL, legacyURL: URL) -> Bool {
        guard remoteExtension(from: remoteURL) == "wav" else { return false }
        return legacyURL.pathExtension.lowercased() == "m4a"
    }

    nonisolated static func extensionMismatch(
        remoteURL: URL,
        cacheExtension: String
    ) -> Bool {
        guard let remote = remoteExtension(from: remoteURL) else { return false }
        return remote != cacheExtension
    }
}
