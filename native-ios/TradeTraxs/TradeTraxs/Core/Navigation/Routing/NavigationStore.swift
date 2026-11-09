import Foundation
import Observation

/// Observable navigation state for the process / scene.
///
/// Owned by ``NavigationEnvironment`` (via CompositionRoot). Not a singleton.
@Observable
final class NavigationStore {
    var sessionPhase: SessionPhase
    var selectedTab: TabIdentifier
    var previousContentTab: TabIdentifier
    var paths: NavigationPathStore
    var presentedSheet: SheetDestination?
    var presentedFullScreen: FullScreenDestination?
    var pendingAfterAuth: PendingDestination?

    /// Optional last-session tab preference (product setting; default Home).
    var restoresLastContentTab: Bool

    /// Bumped by external navigation so the matching destination view and model are recreated.
    /// Session-only — omitted from ``snapshot`` so restoration does not replay a refresh.
    var externalDestinationEpochs: [String: Int] = [:]
    /// Channel/message token for the latest external room open (keyed by ``ExternalDestinationIdentity`` room epoch key).
    var externalRoomFocusTokens: [String: String] = [:]

    init(state: NavigationState = .initial, restoresLastContentTab: Bool = false) {
        self.sessionPhase = state.sessionPhase
        self.selectedTab = state.selectedTab == .create ? state.previousContentTab : state.selectedTab
        self.previousContentTab = state.previousContentTab
        self.paths = NavigationPathStore(
            home: state.homePath,
            feed: state.feedPath,
            messages: state.messagesPath,
            profile: state.profilePath,
            auth: state.authPath
        )
        self.presentedSheet = state.presentedSheet
        self.presentedFullScreen = state.presentedFullScreen
        self.pendingAfterAuth = state.pendingAfterAuth
        self.restoresLastContentTab = restoresLastContentTab
    }

    var snapshot: NavigationState {
        NavigationState(
            sessionPhase: sessionPhase,
            selectedTab: selectedTab == .create ? previousContentTab : selectedTab,
            previousContentTab: previousContentTab,
            homePath: paths.home,
            feedPath: paths.feed,
            messagesPath: paths.messages,
            profilePath: paths.profile,
            authPath: paths.auth,
            presentedSheet: presentedSheet,
            presentedFullScreen: presentedFullScreen,
            pendingAfterAuth: pendingAfterAuth
        )
    }

    func rememberContentTabIfNeeded(_ tab: TabIdentifier) {
        if tab.isContentTab {
            previousContentTab = tab
        }
    }

    func bumpExternalDestinationEpoch(_ key: String) {
        guard !key.isEmpty else { return }
        var epochs = externalDestinationEpochs
        epochs[key, default: 0] += 1
        externalDestinationEpochs = epochs
    }

    /// Stable view identity. The epoch segment changes only after an external open of this destination.
    func externalDestinationIdentity(for key: String) -> String {
        let focusToken = externalRoomFocusTokens[key] ?? ""
        let focusPart = focusToken.isEmpty ? "" : "|\(focusToken)"
        return "\(key)\(focusPart)#\(externalDestinationEpochs[key] ?? 0)"
    }

    func recordExternalRoomFocusToken(routeEpochKey: String, token: String) {
        guard !routeEpochKey.isEmpty else { return }
        var tokens = externalRoomFocusTokens
        tokens[routeEpochKey] = token
        externalRoomFocusTokens = tokens
    }
}
