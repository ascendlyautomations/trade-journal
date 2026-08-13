import Foundation
import OSLog

/// Entry façade for push notification routing.
struct NotificationRouterFacade: Sendable {
    private let router: any NotificationRouting

    init(router: any NotificationRouting = NotificationRouter()) {
        self.router = router
    }

    @MainActor
    func route(
        _ notification: NotificationDestination,
        using coordinator: NavigationCoordinator,
        store: NavigationStore
    ) -> Bool {
        seedRoomFocusIfNeeded(notification)

        guard let destination = router.destination(for: notification) else {
            AppLog.navigation.error("Notification route failed for \(notification.category.rawValue, privacy: .public)")
            return false
        }

        AppLog.navigation.info("Notification resolved: \(String(describing: destination), privacy: .public)")

        if store.sessionPhase != .authenticated {
            coordinator.stashForAuthentication(destination)
            return true
        }

        coordinator.open(destination)
        return true
    }

    @MainActor
    private func seedRoomFocusIfNeeded(_ notification: NotificationDestination) {
        guard let roomID = notification.roomID else { return }
        switch notification.category {
        case .roomMessage, .roomMention:
            RoomNavigationFocusStore.shared.seed(
                roomID: roomID,
                sectionID: notification.sectionID,
                messageID: notification.messageID ?? notification.threadID
            )
        default:
            break
        }
    }
}
