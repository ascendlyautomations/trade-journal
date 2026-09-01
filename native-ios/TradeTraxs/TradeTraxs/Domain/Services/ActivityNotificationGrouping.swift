import Foundation

/// Activity inbox grouping — likes/comments per target; follows & mentions stay individual.
enum ActivityNotificationGrouping {
    struct GroupedItem: Equatable {
        var notification: ActivityNotification
        var actorIDs: [ProfileID]
        var notificationIDs: [NotificationID]
        var primaryText: String
    }

    static func group(
        _ notifications: [ActivityNotification],
        actors: [ProfileID: Profile]
    ) -> [GroupedItem] {
        var likeBuckets: [String: [ActivityNotification]] = [:]
        var commentBuckets: [String: [ActivityNotification]] = [:]
        var likeOrder: [String] = []
        var commentOrder: [String] = []
        var passthrough: [(index: Int, notification: ActivityNotification)] = []

        for (index, notification) in notifications.enumerated() {
            if let key = PushNotificationGrouping.engagementGroupKey(for: notification) {
                if notification.kind == .like {
                    if likeBuckets[key] == nil { likeOrder.append(key) }
                    likeBuckets[key, default: []].append(notification)
                    continue
                }
                if notification.kind == .comment {
                    if commentBuckets[key] == nil { commentOrder.append(key) }
                    commentBuckets[key, default: []].append(notification)
                    continue
                }
            }
            passthrough.append((index, notification))
        }

        // Rebuild chronological order using latest item timestamp per group / single.
        struct Entry {
            var sortDate: Date
            var item: GroupedItem
        }

        var entries: [Entry] = []

        for key in likeOrder {
            guard var bucket = likeBuckets[key], !bucket.isEmpty else { continue }
            bucket.sort { $0.createdAt > $1.createdAt }
            let latest = bucket[0]
            var actorIDs: [ProfileID] = []
            for row in bucket {
                guard let actor = row.actorProfileID, !actorIDs.contains(actor) else { continue }
                actorIDs.append(actor)
            }
            let names = actorIDs.map {
                ActivityNotificationFormatting.actorDisplayName(profile: actors[$0])
            }
            let noun = ActivityNotificationFormatting.engagementTargetLabel(for: latest)
            entries.append(
                Entry(
                    sortDate: latest.createdAt,
                    item: GroupedItem(
                        notification: latest,
                        actorIDs: actorIDs,
                        notificationIDs: bucket.map(\.id),
                        primaryText: PushNotificationGrouping.likeGroupTitle(
                            actorNames: names,
                            total: bucket.count,
                            targetNoun: noun
                        )
                    )
                )
            )
        }

        for key in commentOrder {
            guard var bucket = commentBuckets[key], !bucket.isEmpty else { continue }
            bucket.sort { $0.createdAt > $1.createdAt }
            let latest = bucket[0]
            var actorIDs: [ProfileID] = []
            for row in bucket {
                guard let actor = row.actorProfileID, !actorIDs.contains(actor) else { continue }
                actorIDs.append(actor)
            }
            let names = actorIDs.map {
                ActivityNotificationFormatting.actorDisplayName(profile: actors[$0])
            }
            let noun = ActivityNotificationFormatting.engagementTargetLabel(for: latest)
            let text: String
            if bucket.count == 1 {
                text = ActivityNotificationFormatting.primaryText(
                    for: latest,
                    actorName: names.first ?? "Someone"
                )
            } else {
                text = PushNotificationGrouping.commentGroupTitle(
                    actorNames: names,
                    total: bucket.count,
                    targetNoun: noun
                )
            }
            entries.append(
                Entry(
                    sortDate: latest.createdAt,
                    item: GroupedItem(
                        notification: latest,
                        actorIDs: actorIDs,
                        notificationIDs: bucket.map(\.id),
                        primaryText: text
                    )
                )
            )
        }

        for (_, notification) in passthrough {
            let actor = notification.actorProfileID.flatMap { actors[$0] }
            let name = ActivityNotificationFormatting.actorDisplayName(profile: actor)
            entries.append(
                Entry(
                    sortDate: notification.createdAt,
                    item: GroupedItem(
                        notification: notification,
                        actorIDs: notification.actorProfileID.map { [$0] } ?? [],
                        notificationIDs: [notification.id],
                        primaryText: ActivityNotificationFormatting.primaryText(
                            for: notification,
                            actorName: name
                        )
                    )
                )
            )
        }

        return entries.sorted { $0.sortDate > $1.sortDate }.map(\.item)
    }
}
