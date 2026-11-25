import CoreGraphics
import Foundation

enum BroadcastChatAttachmentPolicy {
    static let chatImageMaxWidth: CGFloat = 160
    static let chatImageMaxHeight: CGFloat = 120
    static let chatImagePlaceholderHeight: CGFloat = 90
    static let chatTradeCardMaxWidth: CGFloat = SharedTradePreviewMetrics.maxCardWidth
    static let chatTradeCardMinHeight: CGFloat = 56
    static let chatTradeCardMaxHeight: CGFloat = SharedTradePreviewMetrics.screenshotMaxHeight + 96

    /// Inner screenshot width for shared trade cards (card max width minus horizontal padding).
    static var chatTradeScreenshotLayoutWidth: CGFloat {
        chatTradeCardMaxWidth - ExperienceSpacing.sm * 2
    }

    /// Trades the viewer may attach in livestream chat (owner's public and private trades; visibility unchanged).
    static func eligibleTradesForSharing(_ trades: [Trade]) -> [Trade] {
        trades
    }

    static func isAllowedBroadcastImageURL(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2_048 else { return false }
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else { return false }
        guard url.scheme?.lowercased() == "https" else { return false }
        guard !host.isEmpty else { return false }
        return true
    }

    /// Upload may return a storage path; resolve to the same HTTPS public object URL DMs use.
    static func resolvedAllowedBroadcastImageURL(
        _ raw: String,
        objectStorage: any ObjectStorageProviding,
        bucket: String = StorageBucket.screenshots.rawValue
    ) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isAllowedBroadcastImageURL(trimmed) {
            return trimmed
        }
        guard let publicURL = objectStorage.publicURL(bucket: bucket, path: trimmed) else {
            return nil
        }
        let absolute = publicURL.absoluteString
        return isAllowedBroadcastImageURL(absolute) ? absolute : nil
    }

    static func sanitizedTradeID(_ raw: String?) -> TradeID? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let id = TradeID(trimmed)
        guard !id.rawValue.isEmpty else { return nil }
        return id
    }
}