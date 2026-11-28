import Foundation

nonisolated struct ProfileInsightsBootstrapV1: Decodable, Sendable {
    struct Meta: Decodable, Sendable {
        var contract_version: String
        var days: Int
        var viewer_id: String
        var engagement_rate_denominator: String?
        var engagement_rate_definition: String?
    }

    struct Coverage: Decodable, Sendable {
        var profile_visits_since: String?
        var content_views_since: String?
        var follower_events_since: String?
        var shares_since: String?
    }

    struct Period: Decodable, Sendable {
        var start: String
        var end: String
        var prior_start: String
        var prior_end: String
    }

    struct Summary: Decodable, Sendable {
        var profile_views: Int?
        var unique_visitors: Int?
        var content_views: Int?
        var content_unique_viewers: Int?
        var new_followers: Int?
        var unfollows: Int?
        var net_followers: Int?
        var likes: Int?
        var comments: Int?
        var saves: Int?
        var shares_initiated: Int?
        var shares_completed: Int?
        var total_engagement: Int?
        var engagement_rate: Double?
    }

    struct DayCount: Decodable, Sendable, Identifiable {
        var day: String
        var count: Int

        var id: String { day }
    }

    struct Series: Decodable, Sendable {
        var profile_views_per_day: [DayCount]?
        var unique_visitors_per_day: [DayCount]?
        var content_views_per_day: [DayCount]?
        var follower_net_per_day: [DayCount]?
        var new_followers_per_day: [DayCount]?
        var unfollows_per_day: [DayCount]?
    }

    struct TopContent: Decodable, Sendable, Identifiable {
        var content_kind: String
        var content_id: String
        var views: Int
        var engagement: Int

        var id: String { "\(content_kind)|\(content_id)" }
    }

    struct DataPayload: Decodable, Sendable {
        var coverage: Coverage
        var period: Period
        var summary: Summary
        var summary_prior: Summary
        var series: Series
        var content_views_by_kind: [String: Int]?
        var top_content: [TopContent]?
        var top_content_by_views: [TopContent]?
        var top_content_by_engagement: [TopContent]?
    }

    var meta: Meta
    var data: DataPayload
}

nonisolated enum ProfileInsightsDayRange: Int, CaseIterable, Identifiable, Sendable {
    case days7 = 7
    case days30 = 30
    case days90 = 90

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .days7: return "7 Days"
        case .days30: return "30 Days"
        case .days90: return "90 Days"
        }
    }
}

nonisolated enum ProfileInsightsPeriodOption: String, CaseIterable, Identifiable, Sendable {
    case days7
    case days30
    case days90
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .days7: return ProfileInsightsDayRange.days7.label
        case .days30: return ProfileInsightsDayRange.days30.label
        case .days90: return ProfileInsightsDayRange.days90.label
        case .custom: return "Custom"
        }
    }

    var preset: ProfileInsightsDayRange? {
        switch self {
        case .days7: return .days7
        case .days30: return .days30
        case .days90: return .days90
        case .custom: return nil
        }
    }
}

nonisolated enum ProfileInsightsTimeScope: Equatable, Sendable {
    case preset(ProfileInsightsDayRange)
    case custom(DateInterval)
}

nonisolated enum ProfileInsightsQuery: Equatable, Sendable, CustomStringConvertible {
    case preset(days: Int)
    case custom(startYMD: String, endYMD: String)

    nonisolated var description: String {
        switch self {
        case .preset(let days): return "preset(\(days))"
        case .custom(let start, let end): return "custom(\(start)…\(end))"
        }
    }
}

nonisolated enum ProfileInsightsDateEncoding {
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    static func utcDayString(for date: Date) -> String {
        let day = utcCalendar.startOfDay(for: date)
        let comps = utcCalendar.dateComponents([.year, .month, .day], from: day)
        guard let y = comps.year, let m = comps.month, let d = comps.day else { return "" }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func query(for scope: ProfileInsightsTimeScope) -> ProfileInsightsQuery {
        switch scope {
        case .preset(let range):
            return .preset(days: range.rawValue)
        case .custom(let interval):
            return .custom(
                startYMD: utcDayString(for: interval.start),
                endYMD: utcDayString(for: interval.end)
            )
        }
    }
}

nonisolated enum ProfileInsightsMath {
    static func percentChange(current: Int?, prior: Int?) -> Double? {
        guard let current, let prior, prior > 0 else { return nil }
        return (Double(current - prior) / Double(prior)) * 100.0
    }
}