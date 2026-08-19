import Foundation
import UIKit

/// Public web URLs for detail Share / Copy Link (matches ``DeepLinkParser`` paths).
enum DetailContentLink: Equatable, Sendable {
    case trade(TradeID)
    case post(PostID)
    case reel(ReelID)
    case achievement(AchievementID)

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
        }
    }

    var absoluteString: String? { url?.absoluteString }

    /// Mail composition for viewer Report (no native moderation API yet).
    var reportMailtoURL: URL? {
        guard let link = absoluteString else { return nil }
        let kind: String = {
            switch self {
            case .trade: return "trade"
            case .post: return "post"
            case .reel: return "reel"
            case .achievement: return "achievement"
            }
        }()
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "support@tradetraxs.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Report \(kind) on TradeTraxs"),
            URLQueryItem(
                name: "body",
                value: "I would like to report this \(kind):\n\n\(link)\n"
            ),
        ]
        return components.url
    }
}

enum DetailOverflowActions {
    @MainActor
    static func copyLink(_ link: DetailContentLink) {
        guard let value = link.absoluteString else { return }
        UIPasteboard.general.string = value
        ExperienceHaptics.play(.success)
    }

    @MainActor
    static func openReport(_ link: DetailContentLink) {
        guard let url = link.reportMailtoURL else { return }
        ExperienceHaptics.play(.selection)
        UIApplication.shared.open(url)
    }
}
