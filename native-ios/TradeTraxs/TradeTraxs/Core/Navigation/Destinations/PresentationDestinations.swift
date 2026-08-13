import Foundation

/// Light presentations — filters, pickers, choosers, comments, follow lists.
enum SheetDestination: String, Identifiable, Hashable, Codable, Sendable {
    case composeChooser
    case quickTrade
    case tradeFilters
    case comments
    case followList
    case shareToMessages
    case accountSwitcher
    case notificationPermission

    var id: String { rawValue }
}

/// Focused multi-step flows — compose, import, onboarding adjacent, upgrade, media.
enum FullScreenDestination: Hashable, Identifiable, Codable, Sendable {
    case addTrade
    case importCSV
    case importReview
    case newPost
    case newAchievement
    case newReel
    case newStory
    case upgrade
    case mediaViewer(MediaViewerContext)
    case storyViewer(StoryID)

    var id: String {
        switch self {
        case .addTrade: return "addTrade"
        case .importCSV: return "importCSV"
        case .importReview: return "importReview"
        case .newPost: return "newPost"
        case .newAchievement: return "newAchievement"
        case .newReel: return "newReel"
        case .newStory: return "newStory"
        case .upgrade: return "upgrade"
        case .mediaViewer(let context): return "mediaViewer.\(context.id)"
        case .storyViewer(let id): return "storyViewer.\(id.rawValue)"
        }
    }
}

enum MediaViewerContext: Hashable, Codable, Sendable {
    case tradeImage(TradeID)
    case postImage(PostID)
    case reel(ReelID)

    var id: String {
        switch self {
        case .tradeImage(let id): return "trade.\(id.rawValue)"
        case .postImage(let id): return "post.\(id.rawValue)"
        case .reel(let id): return "reel.\(id.rawValue)"
        }
    }
}

/// Compose kinds available from the Create action tab / shortcuts.
enum ComposeKind: String, Hashable, Codable, Sendable {
    case chooser
    case trade
    case quickTrade
    case importCSV
    case post
    case achievement
    case reel
    case story
}
