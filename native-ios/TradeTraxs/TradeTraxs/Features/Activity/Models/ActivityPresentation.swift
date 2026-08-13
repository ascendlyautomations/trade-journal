import Foundation

enum ActivityLoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

enum ActivityTimeSection: String, CaseIterable, Identifiable, Hashable {
    case today = "Today"
    case yesterday = "Yesterday"
    case thisWeek = "This Week"
    case earlier = "Earlier"

    var id: String { rawValue }
}

struct ActivityRowModel: Identifiable, Hashable {
    var id: NotificationID
    var notification: ActivityNotification
    var actor: Profile?
    var primaryText: String
    var secondaryText: String?
    var relativeTimestamp: String
    var isUnread: Bool
    var showsSystemIcon: Bool
    /// All Activity rows represented by this card (like/comment groups).
    var groupedNotificationIDs: [NotificationID]

    var accessibilityLabel: String {
        var parts: [String] = []
        if isUnread { parts.append("Unread") }
        parts.append(primaryText)
        if let secondaryText, !secondaryText.isEmpty {
            parts.append(secondaryText)
        }
        parts.append(relativeTimestamp)
        return parts.joined(separator: ". ")
    }
}

struct ActivitySectionModel: Identifiable, Hashable {
    var id: ActivityTimeSection { section }
    var section: ActivityTimeSection
    var rows: [ActivityRowModel]
}

enum ActivityPresentation {
    static func sections(
        from notifications: [ActivityNotification],
        actors: [ProfileID: Profile],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ActivitySectionModel] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfWeek = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday

        var buckets: [ActivityTimeSection: [ActivityRowModel]] = [
            .today: [],
            .yesterday: [],
            .thisWeek: [],
            .earlier: [],
        ]

        let grouped = ActivityNotificationGrouping.group(notifications, actors: actors)
        for item in grouped {
            let notification = item.notification
            let actor = item.actorIDs.first.flatMap { actors[$0] }
            let secondary = ActivityNotificationFormatting.secondaryText(for: notification)

            let row = ActivityRowModel(
                id: notification.id,
                notification: notification,
                actor: actor,
                primaryText: item.primaryText,
                secondaryText: secondary,
                relativeTimestamp: ActivityNotificationFormatting.relativeTimestamp(
                    notification.createdAt,
                    now: now
                ),
                isUnread: item.notificationIDs.contains { id in
                    notifications.first(where: { $0.id == id })?.isRead == false
                },
                showsSystemIcon: notification.kind == .tradingReport
                    || notification.kind == .affiliateReferral
                    || notification.kind == .affiliateCommissionEarned,
                groupedNotificationIDs: item.notificationIDs
            )

            let section: ActivityTimeSection
            if notification.createdAt >= startOfToday {
                section = .today
            } else if notification.createdAt >= startOfYesterday {
                section = .yesterday
            } else if notification.createdAt >= startOfWeek {
                section = .thisWeek
            } else {
                section = .earlier
            }
            buckets[section, default: []].append(row)
        }

        return ActivityTimeSection.allCases.compactMap { section in
            guard let rows = buckets[section], !rows.isEmpty else { return nil }
            return ActivitySectionModel(section: section, rows: rows)
        }
    }
}
