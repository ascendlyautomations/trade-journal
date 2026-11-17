import Foundation

// MARK: - UI selections

nonisolated enum ActivityNotificationDateFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case allTime
    case today
    case yesterday
    case last7Days
    case last30Days
    case custom

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .allTime: return "All Time"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .custom: return "Custom Date Range"
        }
    }

    var compactLabel: String {
        switch self {
        case .allTime: return "All Time"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "7 Days"
        case .last30Days: return "30 Days"
        case .custom: return "Custom"
        }
    }
}

nonisolated enum ActivityNotificationTypeCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case allTypes
    case follows
    case likes
    case comments
    case tradeRooms
    case mentions
    case messages
    case achievements
    case other

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .allTypes: return "All Types"
        case .follows: return "Follows"
        case .likes: return "Likes"
        case .comments: return "Comments"
        case .tradeRooms: return "Trade Rooms"
        case .mentions: return "Mentions"
        case .messages: return "Messages"
        case .achievements: return "Achievements"
        case .other: return "Other"
        }
    }

    var compactLabel: String {
        switch self {
        case .allTypes: return "All Types"
        case .follows: return "Follows"
        case .likes: return "Likes"
        case .comments: return "Comments"
        case .tradeRooms: return "Trade Rooms"
        case .mentions: return "Mentions"
        case .messages: return "Messages"
        case .achievements: return "Achievements"
        case .other: return "Other"
        }
    }
}

/// Server query payload for Activity list fetches (RPC + REST).
nonisolated struct ActivityNotificationListFilter: Hashable, Sendable {
    var types: [String]?
    var achievementPostsOnly: Bool = false
    var excludeAchievementPosts: Bool = false
    var createdAfter: Date?
    var createdBefore: Date?

    static let all = ActivityNotificationListFilter()

    var isActive: Bool {
        types != nil
            || achievementPostsOnly
            || excludeAchievementPosts
            || createdAfter != nil
            || createdBefore != nil
    }

    /// Stable coalesce key for RPC single-flight.
    var cacheKey: String {
        let typeKey = types?.sorted().joined(separator: ",") ?? "-"
        let after = createdAfter.map { ISO8601.string(from: $0) } ?? "-"
        let before = createdBefore.map { ISO8601.string(from: $0) } ?? "-"
        return "\(typeKey)|a=\(achievementPostsOnly)|x=\(excludeAchievementPosts)|\(after)|\(before)"
    }

    func matches(_ notification: ActivityNotification) -> Bool {
        if let types, !types.contains(notification.kind.rawValue) {
            return false
        }
        if achievementPostsOnly, notification.achievementPostID == nil {
            return false
        }
        if excludeAchievementPosts, notification.achievementPostID != nil {
            return false
        }
        if let createdAfter, notification.createdAt < createdAfter {
            return false
        }
        if let createdBefore, notification.createdAt >= createdBefore {
            return false
        }
        return true
    }
}

nonisolated enum ActivityNotificationFilterSupport {
    static func listFilter(
        dateFilter: ActivityNotificationDateFilter,
        customInterval: DateInterval?,
        typeCategory: ActivityNotificationTypeCategory,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ActivityNotificationListFilter {
        var filter = ActivityNotificationListFilter()
        switch typeCategory {
        case .allTypes:
            break
        case .follows:
            filter.types = [
                ActivityNotificationKind.follow.rawValue,
                ActivityNotificationKind.followRequest.rawValue,
                ActivityNotificationKind.followRequestAccepted.rawValue,
            ]
        case .likes:
            filter.types = [ActivityNotificationKind.like.rawValue]
        case .comments:
            filter.types = [ActivityNotificationKind.comment.rawValue]
            filter.excludeAchievementPosts = true
        case .tradeRooms:
            filter.types = [
                ActivityNotificationKind.roomJoin.rawValue,
                ActivityNotificationKind.tradeRoomJoinRequest.rawValue,
                ActivityNotificationKind.tradeRoomJoinAccepted.rawValue,
                ActivityNotificationKind.tradeRoomJoinDeclined.rawValue,
            ]
        case .mentions:
            filter.types = [ActivityNotificationKind.roomMention.rawValue]
        case .messages:
            filter.types = [ActivityNotificationKind.message.rawValue]
        case .achievements:
            filter.types = [
                ActivityNotificationKind.like.rawValue,
                ActivityNotificationKind.comment.rawValue,
            ]
            filter.achievementPostsOnly = true
        case .other:
            filter.types = [
                ActivityNotificationKind.affiliateReferral.rawValue,
                ActivityNotificationKind.affiliateCommissionEarned.rawValue,
                ActivityNotificationKind.tradingReport.rawValue,
            ]
        }

        if let bounds = createdBounds(
            dateFilter: dateFilter,
            customInterval: customInterval,
            now: now,
            calendar: calendar
        ) {
            filter.createdAfter = bounds.after
            filter.createdBefore = bounds.before
        }
        return filter
    }

    static func compactDateLabel(
        dateFilter: ActivityNotificationDateFilter,
        customInterval: DateInterval?
    ) -> String {
        if dateFilter == .custom, let customInterval {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "M/d/yy"
            let start = formatter.string(from: customInterval.start)
            let end = formatter.string(from: customInterval.end)
            return "\(start) – \(end)"
        }
        return dateFilter.compactLabel
    }

    static func isFilterActive(
        dateFilter: ActivityNotificationDateFilter,
        customInterval: DateInterval?,
        typeCategory: ActivityNotificationTypeCategory
    ) -> Bool {
        dateFilter != .allTime || typeCategory != .allTypes
    }

    private static func createdBounds(
        dateFilter: ActivityNotificationDateFilter,
        customInterval: DateInterval?,
        now: Date,
        calendar: Calendar
    ) -> (after: Date?, before: Date?)? {
        switch dateFilter {
        case .allTime:
            return nil
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return (start, end)
        case .yesterday:
            let todayStart = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
            return (start, todayStart)
        case .last7Days:
            let after = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return (after, nil)
        case .last30Days:
            let after = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return (after, nil)
        case .custom:
            guard let customInterval else { return nil }
            let normalized = DashboardScopeFilterSupport.normalizedCustomInterval(
                start: customInterval.start,
                end: customInterval.end,
                calendar: calendar
            )
            let exclusiveEnd = calendar.date(byAdding: .second, value: 1, to: normalized.end) ?? normalized.end
            return (normalized.start, exclusiveEnd)
        }
    }
}