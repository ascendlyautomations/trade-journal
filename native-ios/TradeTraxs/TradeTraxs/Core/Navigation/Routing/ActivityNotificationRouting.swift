import Foundation

/// Maps an Activity row → ``NotificationDestination`` / ``AppDestination``.
///
/// Push / deep-link paths continue to use ``NotificationRouter``. Activity row taps
/// prefer Profile-stack destinations so Back returns to Activity.
enum ActivityNotificationRouting {
    static func notificationDestination(
        for notification: ActivityNotification
    ) -> NotificationDestination {
        switch notification.kind {
        case .followRequest:
            return NotificationDestination(
                category: .followRequest,
                threadID: nil,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                profileID: notification.actorProfileID,
                conversationID: nil,
                roomID: nil,
                reportID: nil,
                rawUserInfo: ["type": notification.kind.rawValue]
            )

        case .tradeRoomJoinRequest:
            return NotificationDestination(
                category: .activity,
                threadID: nil,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                profileID: notification.actorProfileID,
                conversationID: nil,
                roomID: notification.roomID,
                reportID: nil,
                rawUserInfo: [
                    "type": notification.kind.rawValue,
                    "join_request_id": notification.joinRequestID ?? "",
                    "room_slug": notification.roomSlug ?? "",
                    "room_name": notification.roomName ?? "",
                ]
            )

        case .tradeRoomJoinDeclined:
            return NotificationDestination(
                category: .activity,
                threadID: nil,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                profileID: notification.actorProfileID,
                conversationID: nil,
                roomID: notification.roomID,
                reportID: nil,
                rawUserInfo: [
                    "type": notification.kind.rawValue,
                    "room_slug": notification.roomSlug ?? "",
                    "room_name": notification.roomName ?? "",
                ]
            )

        case .roomJoin, .roomMention, .tradeRoomJoinAccepted:
            return NotificationDestination(
                category: notification.kind == .roomMention ? .roomMention : .roomMessage,
                threadID: notification.roomMessageID?.rawValue,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                profileID: notification.actorProfileID,
                conversationID: nil,
                roomID: notification.roomID,
                reportID: nil,
                sectionID: notification.sectionID,
                messageID: notification.roomMessageID?.rawValue,
                rawUserInfo: [
                    "type": notification.kind.rawValue,
                    "room_slug": notification.roomSlug ?? "",
                    "section_id": notification.sectionID ?? "",
                    "message_id": notification.roomMessageID?.rawValue ?? "",
                    "room_name": notification.roomName ?? "",
                    "section_name": notification.sectionName ?? "",
                ]
            )

        case .tradingReport:
            return NotificationDestination(
                category: .tradingReport,
                threadID: nil,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                profileID: nil,
                conversationID: nil,
                roomID: nil,
                reportID: notification.reportID,
                rawUserInfo: ["type": notification.kind.rawValue]
            )

        case .follow, .followRequestAccepted:
            return NotificationDestination(
                category: .activity,
                threadID: nil,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                profileID: notification.actorProfileID,
                conversationID: nil,
                roomID: nil,
                reportID: nil,
                rawUserInfo: ["type": notification.kind.rawValue]
            )

        case .like, .comment:
            let postID = notification.postID
                ?? notification.profilePostID
                ?? notification.achievementPostID
            return NotificationDestination(
                category: .activity,
                threadID: notification.commentID?.rawValue,
                tradeID: notification.tradeID,
                postID: postID,
                reelID: notification.reelID,
                profileID: notification.actorProfileID,
                conversationID: nil,
                roomID: nil,
                reportID: nil,
                rawUserInfo: ["type": notification.kind.rawValue]
            )

        case .affiliateReferral, .affiliateCommissionEarned:
            return NotificationDestination(
                category: .activity,
                threadID: nil,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                profileID: nil,
                conversationID: nil,
                roomID: nil,
                reportID: nil,
                rawUserInfo: [
                    "type": notification.kind.rawValue,
                    "href": notification.affiliateHref ?? "/affiliate/dashboard",
                ]
            )

        case .message:
            return NotificationDestination(
                category: .directMessage,
                threadID: nil,
                tradeID: nil,
                postID: nil,
                reelID: nil,
                profileID: nil,
                conversationID: notification.conversationID,
                roomID: nil,
                reportID: nil,
                rawUserInfo: ["type": "message"]
            )

        case .system:
            return NotificationDestination(
                category: .activity,
                threadID: nil,
                tradeID: notification.tradeID,
                postID: notification.postID,
                reelID: notification.reelID,
                profileID: notification.actorProfileID,
                conversationID: nil,
                roomID: notification.roomID,
                reportID: notification.reportID,
                rawUserInfo: ["type": "system"]
            )
        }
    }

    /// Push onto the Activity screen's tab stack — never switches tabs for preset Feed/Profile parents.
    @MainActor
    static func open(
        _ notification: ActivityNotification,
        host: ActivityNavigationHost,
        coordinator: NavigationCoordinator,
        router: any NotificationRouting = NotificationRouter()
    ) {
        switch host {
        case .home:
            openOnHomeStack(notification, coordinator: coordinator, router: router)
        case .profile:
            openOnProfileStack(notification, coordinator: coordinator, router: router)
        }
    }

    @MainActor
    private static func openOnHomeStack(
        _ notification: ActivityNotification,
        coordinator: NavigationCoordinator,
        router: any NotificationRouting
    ) {
        switch notification.kind {
        case .followRequest:
            coordinator.pushHome(.followRequests)
        case .tradeRoomJoinRequest:
            if let joinRequestID = notification.joinRequestID, !joinRequestID.isEmpty {
                coordinator.pushHome(.tradeRoomJoinRequest(joinRequestID))
            } else {
                coordinator.pushHome(.activity)
            }
        case .tradeRoomJoinAccepted, .tradeRoomJoinDeclined:
            if let roomID = notification.roomID {
                coordinator.pushHome(.room(roomID))
            } else {
                coordinator.pushHome(.rooms)
            }
        case .follow, .followRequestAccepted:
            if let profileID = notification.actorProfileID {
                coordinator.pushHome(.otherProfile(profileID))
            } else {
                coordinator.pushHome(.activity)
            }
        case .like, .comment:
            if let reelID = notification.reelID {
                coordinator.pushHome(.reel(reelID))
            } else if let achievementPostID = notification.achievementPostID {
                coordinator.pushHome(.achievementDetail(AchievementID(achievementPostID.rawValue)))
            } else if let postID = notification.postID ?? notification.profilePostID {
                coordinator.pushHome(.post(postID))
            } else if let tradeID = notification.tradeID {
                coordinator.pushHome(.socialTrade(tradeID))
            } else if let profileID = notification.actorProfileID {
                coordinator.pushHome(.otherProfile(profileID))
            } else {
                coordinator.pushHome(.activity)
            }
        case .roomJoin, .roomMention:
            if let roomID = notification.roomID {
                coordinator.pushHome(.room(roomID))
            } else {
                coordinator.pushHome(.rooms)
            }
        case .tradingReport:
            if let reportID = notification.reportID {
                coordinator.pushHome(.report(reportID))
            }
        case .affiliateReferral, .affiliateCommissionEarned:
            if IosSubscriptionReleaseConfiguration.iosReferralProgramEnabled {
                coordinator.pushHome(.affiliate)
            } else {
                coordinator.pushHome(.activity)
            }
        case .message, .system:
            pushExternalDestination(
                router.destination(for: notificationDestination(for: notification)),
                coordinator: coordinator,
                fallback: { coordinator.pushHome(.activity) }
            )
        }
    }

    @MainActor
    private static func openOnProfileStack(
        _ notification: ActivityNotification,
        coordinator: NavigationCoordinator,
        router: any NotificationRouting
    ) {
        switch notification.kind {
        case .followRequest:
            coordinator.pushProfile(.followRequests)
        case .tradeRoomJoinRequest:
            if let joinRequestID = notification.joinRequestID, !joinRequestID.isEmpty {
                coordinator.pushProfile(.tradeRoomJoinRequest(joinRequestID))
            } else {
                coordinator.pushProfile(.activity)
            }
        case .tradeRoomJoinAccepted, .tradeRoomJoinDeclined:
            if let roomID = notification.roomID {
                coordinator.pushProfile(.room(roomID))
            } else {
                coordinator.pushProfile(.rooms)
            }
        case .follow, .followRequestAccepted:
            if let profileID = notification.actorProfileID {
                coordinator.pushProfile(.otherProfile(profileID))
            } else {
                coordinator.pushProfile(.activity)
            }
        case .like, .comment:
            if let reelID = notification.reelID {
                coordinator.pushProfile(.reel(reelID))
            } else if let achievementPostID = notification.achievementPostID {
                coordinator.pushProfile(.achievement(AchievementID(achievementPostID.rawValue)))
            } else if let postID = notification.postID ?? notification.profilePostID {
                coordinator.pushProfile(.post(postID))
            } else if let tradeID = notification.tradeID {
                coordinator.pushProfile(.trade(tradeID))
            } else if let profileID = notification.actorProfileID {
                coordinator.pushProfile(.otherProfile(profileID))
            } else {
                coordinator.pushProfile(.activity)
            }
        case .roomJoin, .roomMention:
            if let roomID = notification.roomID {
                coordinator.pushProfile(.room(roomID))
            } else {
                coordinator.pushProfile(.rooms)
            }
        case .tradingReport:
            if let reportID = notification.reportID {
                coordinator.pushHome(.report(reportID))
            }
        case .affiliateReferral, .affiliateCommissionEarned:
            if IosSubscriptionReleaseConfiguration.iosReferralProgramEnabled {
                coordinator.pushProfile(.affiliate)
            } else {
                coordinator.pushProfile(.activity)
            }
        case .message, .system:
            pushExternalDestination(
                router.destination(for: notificationDestination(for: notification)),
                coordinator: coordinator,
                fallback: { coordinator.pushProfile(.activity) }
            )
        }
    }

    @MainActor
    private static func pushExternalDestination(
        _ destination: AppDestination?,
        coordinator: NavigationCoordinator,
        fallback: () -> Void
    ) {
        guard let destination else {
            fallback()
            return
        }
        switch destination {
        case .messages(let route):
            coordinator.pushMessages(route)
        case .home(let route):
            coordinator.pushHome(route)
        case .feed(let route):
            coordinator.pushFeed(route)
        case .profile(let route):
            coordinator.pushProfile(route)
        case .tab(let tab):
            coordinator.selectTab(tab)
        case .sheet(let sheet):
            coordinator.present(sheet: sheet)
        case .fullScreen(let cover):
            coordinator.present(fullScreen: cover)
        case .compose(let kind):
            coordinator.openCompose(kind)
        case .settingsStack:
            coordinator.open(destination)
        case .auth, .pop, .popToRoot, .dismissPresentation:
            fallback()
        }
    }

    /// Activity-local destination resolution (legacy — prefer ``open(_:host:coordinator:router:)``).
    static func appDestination(
        for notification: ActivityNotification,
        router: any NotificationRouting = NotificationRouter()
    ) -> AppDestination {
        switch notification.kind {
        case .followRequest:
            return .profile(.followRequests)

        case .tradeRoomJoinRequest:
            if let joinRequestID = notification.joinRequestID, !joinRequestID.isEmpty {
                return .profile(.tradeRoomJoinRequest(joinRequestID))
            }
            return .profile(.activity)

        case .tradeRoomJoinAccepted, .tradeRoomJoinDeclined:
            if let roomID = notification.roomID {
                return .profile(.room(roomID))
            }
            return .profile(.rooms)

        case .follow, .followRequestAccepted:
            if let profileID = notification.actorProfileID {
                return .profile(.otherProfile(profileID))
            }
            return .profile(.activity)

        case .like, .comment:
            if let reelID = notification.reelID {
                return .profile(.reel(reelID))
            }
            if let achievementPostID = notification.achievementPostID {
                // `achievement_post_id` resolves inside AchievementDetail (posts → achievements).
                return .profile(.achievement(AchievementID(achievementPostID.rawValue)))
            }
            if let postID = notification.postID ?? notification.profilePostID {
                return .profile(.post(postID))
            }
            if let tradeID = notification.tradeID {
                return .profile(.trade(tradeID))
            }
            if let profileID = notification.actorProfileID {
                return .profile(.otherProfile(profileID))
            }
            return .profile(.activity)

        case .roomJoin, .roomMention:
            if let roomID = notification.roomID {
                return .profile(.room(roomID))
            }
            return .profile(.rooms)

        case .tradingReport:
            if let reportID = notification.reportID {
                return .home(.report(reportID))
            }
            return .tab(.home)

        case .affiliateReferral, .affiliateCommissionEarned:
            guard IosSubscriptionReleaseConfiguration.iosReferralProgramEnabled else {
                return .profile(.activity)
            }
            return .profile(.affiliate)

        case .message:
            return router.destination(for: notificationDestination(for: notification))
                ?? .tab(.messages)

        case .system:
            return router.destination(for: notificationDestination(for: notification))
                ?? .profile(.activity)
        }
    }
}
