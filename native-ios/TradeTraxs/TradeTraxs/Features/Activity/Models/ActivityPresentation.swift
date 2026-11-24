import Foundation

enum ActivityLoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}

/// Chronological inbox sections, newest sections first; each notification belongs to exactly one bucket.
enum ActivityTimeSection: String, CaseIterable, Identifiable, Hashable {
    case today = "Today"
    case yesterday = "Yesterday"
    case thisWeek = "This Week"
    case lastWeek = "Last Week"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case older = "Older"

    var id: String { rawValue }

    /// Display order, newest window first.
    static let displayOrder: [ActivityTimeSection] = [
        .today, .yesterday, .thisWeek, .lastWeek, .thisMonth, .lastMonth, .older,
    ]
}

struct ActivityRowModel: Identifiable, Hashable {
    var id: NotificationID
    var notification: ActivityNotification
    var actor: Profile?
    var primaryText: String
    var secondaryText: String?
    var relativeTimestamp: String
    var isUnread: Bool
    var usesTradeTraxsBrandAvatar: Bool
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

/// Inclusive/exclusive day boundaries for mutual-exclusive Activity sections (local ``Calendar``).
struct ActivityTimeSectionBoundaries: Equatable {
    let startOfToday: Date
    let startOfYesterday: Date
    let startOfThisWeek: Date
    let startOfLastWeek: Date
    let startOfThisMonth: Date
    let startOfLastMonth: Date

    init(now: Date, calendar: Calendar) {
        startOfToday = calendar.startOfDay(for: now)
        startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        startOfThisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        let lastWeekAnchor = calendar.date(byAdding: .day, value: -1, to: startOfThisWeek) ?? startOfThisWeek
        startOfLastWeek = calendar.dateInterval(of: .weekOfYear, for: lastWeekAnchor)?.start ?? startOfThisWeek
        startOfThisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
        startOfLastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth) ?? startOfThisMonth
    }

    func section(for createdAt: Date) -> ActivityTimeSection {
        if createdAt >= startOfToday {
            return .today
        }
        if createdAt >= startOfYesterday {
            return .yesterday
        }
        if createdAt >= startOfThisWeek {
            return .thisWeek
        }
        if createdAt >= startOfLastWeek {
            return .lastWeek
        }
        if createdAt >= startOfThisMonth {
            return .thisMonth
        }
        if createdAt >= startOfLastMonth {
            return .lastMonth
        }
        return .older
    }
}

enum ActivityPresentation {
    static func sections(
        from notifications: [ActivityNotification],
        actors: [ProfileID: Profile],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ActivitySectionModel] {
        let boundaries = ActivityTimeSectionBoundaries(now: now, calendar: calendar)

        var buckets: [ActivityTimeSection: [ActivityRowModel]] = [:]

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
                usesTradeTraxsBrandAvatar: notification.usesTradeTraxsBrandAvatar,
                groupedNotificationIDs: item.notificationIDs
            )

            let section = boundaries.section(for: notification.createdAt)
            buckets[section, default: []].append(row)
        }

        return ActivityTimeSection.displayOrder.compactMap { section in
            guard var rows = buckets[section], !rows.isEmpty else { return nil }
            rows.sort { $0.notification.createdAt > $1.notification.createdAt }
            return ActivitySectionModel(section: section, rows: rows)
        }
    }
}