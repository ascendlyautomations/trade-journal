import Foundation
import OSLog

/// Entry façade for universal links and custom schemes.
///
/// Parses once, then applies through ``NavigationCoordinator``.
struct DeepLinkRouter: Sendable {
    private let parser: any DeepLinkParsing

    init(parser: any DeepLinkParsing = DeepLinkParser()) {
        self.parser = parser
    }

    @MainActor
    func route(url: URL, using coordinator: NavigationCoordinator, store: NavigationStore) -> Bool {
        guard let destination = parser.parse(url: url) else {
            AppLog.navigation.error("Deep link parse failed: \(url.absoluteString, privacy: .public)")
            return false
        }

        seedRoomFocus(from: url, destination: destination)

        AppLog.navigation.info("Deep link resolved: \(String(describing: destination), privacy: .public)")

        if store.sessionPhase != .authenticated {
            switch destination {
            case .auth:
                coordinator.open(destination)
            default:
                coordinator.stashForAuthentication(destination)
            }
            return true
        }

        coordinator.open(destination)
        return true
    }

    @MainActor
    private func seedRoomFocus(from url: URL, destination: AppDestination) {
        let query = url.queryItemsDictionary
        let section = query["section"]
        let message = query["message"]
        guard section != nil || message != nil else { return }

        let roomID: RoomID?
        switch destination {
        case .feed(.room(let id)), .messages(.room(let id)), .profile(.room(let id)):
            roomID = id
        default:
            if let room = query["room"], !room.isEmpty {
                roomID = RoomID(room)
            } else {
                roomID = nil
            }
        }
        guard let roomID else { return }
        RoomNavigationFocusStore.shared.seed(
            roomID: roomID,
            sectionID: section,
            messageID: message
        )
    }
}
