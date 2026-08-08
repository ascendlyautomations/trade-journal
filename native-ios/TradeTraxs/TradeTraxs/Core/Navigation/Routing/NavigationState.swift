import Foundation

/// Codable snapshot of navigation for scene / process restoration.
struct NavigationState: Codable, Hashable, Sendable {
    var sessionPhase: SessionPhase
    var selectedTab: TabIdentifier
    /// Content tab to restore after Create action.
    var previousContentTab: TabIdentifier
    var homePath: [HomeRoute]
    var feedPath: [FeedRoute]
    var messagesPath: [MessagesRoute]
    var profilePath: [ProfileRoute]
    var authPath: [AuthRoute]
    var presentedSheet: SheetDestination?
    var presentedFullScreen: FullScreenDestination?
    /// Destination stashed until authentication completes.
    var pendingAfterAuth: PendingDestination?

    static var initial: NavigationState {
        NavigationState(
            sessionPhase: .unauthenticated,
            selectedTab: .home,
            previousContentTab: .home,
            homePath: [],
            feedPath: [],
            messagesPath: [],
            profilePath: [],
            authPath: [],
            presentedSheet: nil,
            presentedFullScreen: nil,
            pendingAfterAuth: nil
        )
    }
}

/// Codable subset of ``AppDestination`` that can wait for auth.
enum PendingDestination: Codable, Hashable, Sendable {
    case tab(TabIdentifier)
    case home(HomeRoute)
    case feed(FeedRoute)
    case messages(MessagesRoute)
    case profile(ProfileRoute)
    case compose(ComposeKind)
    case fullScreen(FullScreenDestination)
    case sheet(SheetDestination)

    init?(destination: AppDestination) {
        switch destination {
        case .tab(let tab): self = .tab(tab)
        case .home(let route): self = .home(route)
        case .feed(let route): self = .feed(route)
        case .messages(let route): self = .messages(route)
        case .profile(let route): self = .profile(route)
        case .compose(let kind): self = .compose(kind)
        case .fullScreen(let destination): self = .fullScreen(destination)
        case .sheet(let destination): self = .sheet(destination)
        case .auth, .pop, .popToRoot, .dismissPresentation:
            return nil
        }
    }

    var asAppDestination: AppDestination {
        switch self {
        case .tab(let tab): return .tab(tab)
        case .home(let route): return .home(route)
        case .feed(let route): return .feed(route)
        case .messages(let route): return .messages(route)
        case .profile(let route): return .profile(route)
        case .compose(let kind): return .compose(kind)
        case .fullScreen(let destination): return .fullScreen(destination)
        case .sheet(let destination): return .sheet(destination)
        }
    }
}
