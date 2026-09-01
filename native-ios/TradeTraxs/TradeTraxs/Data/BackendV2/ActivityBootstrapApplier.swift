import Foundation

nonisolated enum ActivityBootstrapApplier {
    struct Applied: Sendable {
        var items: [ActivityNotification]
        var unreadCount: Int
        var pendingFollowRequestCount: Int
        var nextCursor: String?
    }

    @MainActor
    static func apply(
        _ bootstrap: ActivityBootstrapV1,
        detailCache: DetailPresentationCache?
    ) -> Applied {
        let notifications = bootstrap.data.notifications.compactMap {
            DefaultNotificationRepository.mapNotification($0.asNotificationDTO())
        }

        if let detailCache {
            for (_, card) in bootstrap.data.actors {
                if let profile = mapActor(card) {
                    detailCache.seed(profile)
                }
            }
        }

        return Applied(
            items: notifications,
            unreadCount: bootstrap.data.unread_total,
            pendingFollowRequestCount: bootstrap.data.follow_requests.count,
            nextCursor: bootstrap.data.next_cursor
        )
    }

    private static func mapActor(_ card: AuthorCardV1) -> Profile? {
        let dto = ProfileDTO.Profile(
            id: card.id,
            username: card.username,
            name: card.display_name,
            bio: nil,
            avatar_url: card.avatar_url,
            trader_type: nil,
            trading_style: nil,
            primary_market: nil,
            started_trading: nil,
            is_private: nil,
            is_creator: nil,
            is_pro: nil,
            subscription_status: nil,
            created_at: nil,
            referral_code: nil
        )
        return try? ProfileMapper.mapToDomain(dto)
    }
}
