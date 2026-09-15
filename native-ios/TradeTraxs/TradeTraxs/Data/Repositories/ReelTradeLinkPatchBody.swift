import Foundation

/// PATCH payload when linking an existing reel to a trade — does not modify caption.
nonisolated struct ReelTradeLinkPatchBody: Encodable, Sendable {
    var trade_id: String
    var visibility: String

    init(tradeID: String, tradeIsPublic: Bool) {
        trade_id = tradeID
        visibility = tradeIsPublic ? "public" : "private"
    }
}
