import Foundation
import UIKit

/// Public web URLs for detail Share / Copy Link (matches ``DeepLinkParser`` paths).
enum DetailContentLink: Equatable, Sendable {
    case trade(TradeID)
    case post(PostID)
    case reel(ReelID)
    case achievement(AchievementID)
    case story(StoryID)

    var url: URL? {
        switch self {
        case .trade(let id):
            return URL(string: "https://www.tradetraxs.com/trade/\(id.rawValue)")
        case .post(let id):
            return URL(string: "https://www.tradetraxs.com/post/\(id.rawValue)")
        case .reel(let id):
            return URL(string: "https://www.tradetraxs.com/reel/\(id.rawValue)")
        case .achievement(let id):
            return URL(string: "https://www.tradetraxs.com/feed?achievement=\(id.rawValue)")
        case .story(let id):
            return URL(string: "https://www.tradetraxs.com/story/\(id.rawValue)")
        }
    }

    var absoluteString: String? { url?.absoluteString }
}

enum DetailOverflowActions {
    @MainActor
    static func copyLink(_ link: DetailContentLink) {
        guard let value = link.absoluteString else { return }
        UIPasteboard.general.string = value
        ExperienceHaptics.play(.success)
    }
}
