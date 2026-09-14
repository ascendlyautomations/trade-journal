import Foundation

nonisolated enum ActivityBootstrapApplier {
    struct Applied: Sendable {
        var items: [ActivityNotification]
        var unreadCount: Int
        var pendingFollowRequestCount: Int
        var nextCursor: String?
        var actorProfiles: [Profile]
    }

    /// Decode/transform off the MainActor — no detail-cache mutation.
    nonisolated static func transform(_ bootstrap: ActivityBootstrapV1) -> Applied {
        let decodedCount = bootstrap.data.notifications.count
        let notifications = bootstrap.data.notifications.compactMap {
            DefaultNotificationRepository.mapNotification($0.asNotificationDTO())
        }
        let actorProfiles = bootstrap.data.actors.values.compactMap { mapActor($0) }
        ActivityPipelineProbe.record(
            stage: "rpcDecoded",
            decoded: decodedCount,
            stored: notifications.count,
            note: decodedCount > notifications.count ? "mappingDropped=\(decodedCount - notifications.count)" : nil
        )
        return Applied(
            items: notifications,
            unreadCount: bootstrap.data.unread_total,
            pendingFollowRequestCount: bootstrap.data.follow_requests.count,
            nextCursor: bootstrap.data.next_cursor,
            actorProfiles: actorProfiles
        )
    }

    @MainActor
    static func seedActors(_ profiles: [Profile], detailCache: DetailPresentationCache?) {
        guard let detailCache, !profiles.isEmpty else { return }
        MainThreadWorkProbe.measure("activity.seedActors", surface: "activity") {
            for profile in profiles {
                detailCache.seed(profile)
            }
        }
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
