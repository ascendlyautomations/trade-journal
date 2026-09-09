import Foundation
import UIKit

/// Local-only clip draft. Upload + `reels` insert happen on publish / Save Trade.
struct ReelDraft: Equatable {
    var selectionID: String
    /// App-owned source kept until publish / replace / dismiss.
    var ownedSourceURL: URL?
    /// Transcoded delivery file used for upload + preview.
    var localVideoURL: URL
    var contentType: String
    var byteCount: Int
    var durationSeconds: Int
    var thumbnailJPEG: Data?
    var thumbnailPreview: UIImage?
    /// Standalone caption (`reels.caption`). Must stay nil when trade-linked (DB check).
    var caption: String = ""
    var linkedTradeID: TradeID?
    /// Compact trade summary for UI (loaded only when user picks a trade).
    var linkedTradeSummary: String?

    var hasVideo: Bool { true }

    var formattedDuration: String {
        MediaVideoPreparation.formatDuration(durationSeconds)
    }

    static func == (lhs: ReelDraft, rhs: ReelDraft) -> Bool {
        lhs.selectionID == rhs.selectionID
            && lhs.ownedSourceURL == rhs.ownedSourceURL
            && lhs.localVideoURL == rhs.localVideoURL
            && lhs.contentType == rhs.contentType
            && lhs.byteCount == rhs.byteCount
            && lhs.durationSeconds == rhs.durationSeconds
            && lhs.caption == rhs.caption
            && lhs.linkedTradeID == rhs.linkedTradeID
            && lhs.linkedTradeSummary == rhs.linkedTradeSummary
            && lhs.thumbnailJPEG == rhs.thumbnailJPEG
    }
}
