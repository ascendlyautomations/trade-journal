import Foundation

/// Profile browse-card media gating — attachment presence only (not load/failure state).
enum ProfileCardMediaPresence {
    static func postMedia(in post: Post) -> MediaReference? {
        post.media.first {
            !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func tradeMedia(in trade: Trade) -> MediaReference? {
        tradeMedia(thumbnail: trade.thumbnail)
    }

    static func tradeMedia(in summary: TradeSummary) -> MediaReference? {
        tradeMedia(thumbnail: summary.thumbnail)
    }

    private static func tradeMedia(thumbnail: MediaReference?) -> MediaReference? {
        guard let thumbnail else { return nil }
        let trimmed = thumbnail.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : thumbnail
    }

    /// Vault is hidden on the viewer's own profile cards; shown when browsing another profile.
    static func engagementVaultRef(
        for target: InteractionTarget,
        profileIsOwner: Bool
    ) -> VaultContentRef? {
        profileIsOwner ? nil : VaultContentRef.from(target)
    }
}
