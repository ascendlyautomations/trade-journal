import Foundation

enum CommentTradeShareSupport {
    /// All viewer-owned trades (public, followers-only, and private). Private attachments
    /// are readable by anyone who can read the comment via comment-scoped RLS — no `is_public` change.
    static func eligibleForAttachment(_ trades: [Trade], viewerID: ProfileID) -> [Trade] {
        trades.filter { $0.ownerProfileID == viewerID }
    }

    static let privateAttachmentDisclaimer =
        "Private trade — anyone who can view this comment can open the attached trade."
}