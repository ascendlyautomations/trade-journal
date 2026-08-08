import Foundation

/// Typed, app-wide navigation intent.
///
/// Views and system entry points emit ``AppDestination``.
/// ``NavigationCoordinator`` applies it to ``NavigationStore``.
/// No string-based routing inside features.
enum AppDestination: Hashable, Sendable {
    case auth(AuthRoute)
    case tab(TabIdentifier)
    case home(HomeRoute)
    case feed(FeedRoute)
    case messages(MessagesRoute)
    case profile(ProfileRoute)
    case sheet(SheetDestination)
    case fullScreen(FullScreenDestination)
    case compose(ComposeKind)
    case pop
    case popToRoot(TabIdentifier?)
    case dismissPresentation
}

/// External URL / custom-scheme intent before parsing into ``AppDestination``.
enum DeepLinkDestination: Hashable, Sendable {
    case url(URL)
}

/// Push notification payload intent before mapping into ``AppDestination``.
struct NotificationDestination: Hashable, Sendable {
    let category: NotificationCategory
    let threadID: String?
    let tradeID: TradeID?
    let postID: PostID?
    let reelID: ReelID?
    let profileID: ProfileID?
    let conversationID: ConversationID?
    let roomID: RoomID?
    let reportID: ReportID?
    let rawUserInfo: [String: String]

    enum NotificationCategory: String, Hashable, Codable, Sendable {
        case activity
        case directMessage
        case roomMessage
        case roomMention
        case followRequest
        case tradingReport
        case unknown
    }
}

/// High-level session gate for the root shell.
enum SessionPhase: String, Codable, Hashable, Sendable {
    /// Auth stack visible (login / onboarding / plan).
    case unauthenticated
    /// Main tab shell visible.
    case authenticated
}
