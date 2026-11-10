import Foundation

/// Profile / clip card title — stored reel caption; generic label when empty.
enum ClipDisplayTitle {
    static func text(for reel: Reel, linkedTrade _: Trade?) -> String {
        ReelCaptionDisplay.displayText(for: reel)
    }

    static func text(for reel: Reel, cache: DetailPresentationCache) -> String {
        ReelCaptionDisplay.displayText(for: reel, cache: cache)
    }
}
