import Foundation

/// Profile browse-card media gating — attachment presence only (not load/failure state).
enum ProfileCardMediaPresence {
    static func postMedia(in post: Post) -> MediaReference? {
        post.media.first {
            !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func tradeMedia(in trade: Trade) -> MediaReference? {
        guard let thumbnail = trade.thumbnail else { return nil }
        let trimmed = thumbnail.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : thumbnail
    }
}
