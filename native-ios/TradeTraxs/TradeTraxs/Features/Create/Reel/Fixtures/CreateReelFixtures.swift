import Foundation
import UIKit

enum CreateReelFixtures {
    static let viewerID = ProfileID("dev.create-reel")

    static func sampleTrade(owner: ProfileID = viewerID) -> Trade {
        Trade(
            id: TradeID("dev-reel-trade-1"),
            ownerProfileID: owner,
            accountID: TradingAccountID("dev-acct"),
            symbol: Symbol(ticker: "MNQ"),
            side: .long,
            mode: .live,
            quantity: 2,
            entryPrice: Decimal(string: "21452.25"),
            exitPrice: Decimal(string: "21468.75"),
            entryAt: Date(timeIntervalSince1970: 1_723_300_000),
            exitAt: Date(timeIntervalSince1970: 1_723_300_360),
            realizedPnL: Money(amount: 660),
            riskReward: Decimal(string: "2.35"),
            points: Decimal(string: "16.5"),
            sessionLabel: "NY",
            visibility: .public,
            publicCaption: "Liquidity sweep long",
            thumbnail: MediaReference(
                id: "https://example.com/dev-reel-trade.jpg",
                kind: .image,
                altText: "Trade screenshot"
            ),
            notePreview: nil,
            createdAt: Date(timeIntervalSince1970: 1_723_300_000),
            updatedAt: Date(timeIntervalSince1970: 1_723_300_000)
        )
    }

    static func sampleTrades(owner: ProfileID = viewerID) -> [Trade] {
        [sampleTrade(owner: owner)]
    }

    static func sampleReel(author: ProfileID = viewerID, tradeID: TradeID? = nil) -> Reel {
        Reel(
            id: ReelID("dev-reel-created"),
            authorProfileID: author,
            video: MediaReference(id: "https://example.com/dev-reel.mp4", kind: .video, altText: nil),
            thumbnail: MediaReference(id: "https://example.com/dev-reel-thumb.jpg", kind: .image, altText: nil),
            caption: tradeID == nil ? "Standalone clip caption" : nil,
            visibility: .public,
            linkedTradeID: tradeID,
            durationSeconds: 12,
            createdAt: .now
        )
    }

    /// Tiny placeholder JPEG for DEBUG screenshot / unit draft previews.
    static func placeholderThumbnail() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 180, height: 320))
        return renderer.image { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 180, height: 320))
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 65, y: 135, width: 50, height: 50)).fill()
        }
    }

    static func screenshotDraft(linkedTrade: Trade? = nil) -> ReelDraft {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("uitesting-reel-\(UUID().uuidString).mov")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data([0x00, 0x00]), attributes: nil)
        }
        let thumb = placeholderThumbnail()
        return ReelDraft(
            localVideoURL: url,
            contentType: "video/quicktime",
            byteCount: 2,
            durationSeconds: 12,
            thumbnailJPEG: thumb.jpegData(compressionQuality: 0.8),
            thumbnailPreview: thumb,
            caption: linkedTrade == nil ? "Took the sweep and held for the target." : "",
            linkedTradeID: linkedTrade?.id,
            linkedTradeSummary: linkedTrade.map {
                "\($0.symbol.ticker) · \($0.side.rawValue.capitalized)"
            }
        )
    }
}
