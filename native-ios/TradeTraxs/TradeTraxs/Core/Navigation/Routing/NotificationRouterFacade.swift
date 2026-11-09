import Foundation
import OSLog

/// Entry façade for push notification routing.
nonisolated struct NotificationRouterFacade: Sendable {
    private let router: any NotificationRouting

    init(router: any NotificationRouting) {
        self.router = router
    }

    @MainActor
    func route(
        _ notification: NotificationDestination,
        using coordinator: NavigationCoordinator,
        store: NavigationStore
    ) -> Bool {
        registerRoomAliasIfNeeded(notification)
        seedRoomFocusIfNeeded(notification)
        seedConversationFocusIfNeeded(notification)

        guard let destination = router.destination(for: notification) else {
            AppLog.navigation.error("Notification route failed for \(notification.category.rawValue, privacy: .public)")
            return false
        }

        AppLog.navigation.info("Notification resolved: \(String(describing: destination), privacy: .public)")
        RoomNotificationNavigationTrace.event(
            .init(
                stage: "facade.route",
                roomID: notification.roomID?.rawValue,
                sectionID: notification.sectionID,
                sectionName: notification.rawUserInfo["section_name"],
                messageID: notification.messageID,
                destination: String(describing: destination)
            )
        )

        if store.sessionPhase != .authenticated {
            coordinator.stashForAuthentication(destination)
            return true
        }

        coordinator.openExternal(destination)
        return true
    }

    @MainActor
    private func registerRoomAliasIfNeeded(_ notification: NotificationDestination) {
        guard let roomID = notification.roomID else { return }
        var ids = [roomID]
        if let slug = notification.rawUserInfo["room_slug"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !slug.isEmpty
        {
            ids.append(RoomID(slug))
        }
        RoomNavigationFocusStore.shared.registerRoomAlias(ids)
    }

    @MainActor
    private func seedRoomFocusIfNeeded(_ notification: NotificationDestination) {
        guard let roomID = notification.roomID else { return }
        let openLive = Self.hrefRequestsLiveWatch(notification.rawUserInfo["href"])

        let type = (notification.rawUserInfo["type"] ?? "").lowercased()

        switch notification.category {
        case .roomMessage, .roomMention:
            RoomNavigationFocusStore.shared.seed(
                roomID: roomID,
                sectionID: notification.sectionID,
                messageID: notification.messageID ?? notification.threadID,
                sectionName: notification.rawUserInfo["section_name"],
                openLiveBroadcast: openLive
            )
        default:
            if openLive || type == "room_live" {
                RoomNavigationFocusStore.shared.seed(
                    roomID: roomID,
                    sectionID: nil,
                    messageID: nil,
                    openLiveBroadcast: true
                )
            }
        }
    }

    @MainActor
    private func seedConversationFocusIfNeeded(_ notification: NotificationDestination) {
        guard notification.category == .directMessage,
              let conversationID = notification.conversationID
        else { return }
        ConversationNavigationFocusStore.shared.seed(
            conversationID: conversationID,
            messageID: notification.messageID ?? notification.threadID
        )
    }

    private static func hrefRequestsLiveWatch(_ href: String?) -> Bool {
        guard let href, !href.isEmpty else { return false }
        let url: URL?
        if href.hasPrefix("http") {
            url = URL(string: href)
        } else if href.hasPrefix("/") {
            url = URL(string: "https://www.tradetraxs.com\(href)")
        } else {
            url = URL(string: href)
        }
        guard let url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return false }
        return items.contains { item in
            item.name == "live" && (item.value == "1" || item.value?.lowercased() == "true")
        }
    }
}
