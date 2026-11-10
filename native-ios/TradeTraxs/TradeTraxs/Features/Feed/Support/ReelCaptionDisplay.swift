import Foundation

/// Canonical clip caption — `reels.caption` first; legacy trade-linked rows before Sep 2026 may use trade text.
enum ReelCaptionDisplay {
    static let emptyFallback = "Clip"

    static func displayText(for reel: Reel) -> String {
        resolvedDisplayText(for: reel, cache: nil)
    }

    static func displayText(for reel: Reel, cache: DetailPresentationCache) -> String {
        resolvedDisplayText(for: cache.reel(id: reel.id) ?? reel, cache: cache)
    }

    /// Non-empty caption for body/overlay regions; nil when there is nothing to show beyond the fallback label.
    static func bodyText(for reel: Reel) -> String? {
        resolvedBodyText(for: reel, cache: nil)
    }

    static func bodyText(for reel: Reel, cache: DetailPresentationCache) -> String? {
        resolvedBodyText(for: cache.reel(id: reel.id) ?? reel, cache: cache)
    }

    private static func resolvedDisplayText(for reel: Reel, cache: DetailPresentationCache?) -> String {
        if let caption = normalized(reel.caption) { return caption }
        if let cache, let legacy = ReelCaptionLegacySupport.displayFallbackCaption(for: reel, cache: cache) {
            return legacy
        }
        return emptyFallback
    }

    private static func resolvedBodyText(for reel: Reel, cache: DetailPresentationCache?) -> String? {
        if let caption = normalized(reel.caption) { return caption }
        if let cache {
            return ReelCaptionLegacySupport.displayFallbackCaption(for: reel, cache: cache)
        }
        return nil
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
