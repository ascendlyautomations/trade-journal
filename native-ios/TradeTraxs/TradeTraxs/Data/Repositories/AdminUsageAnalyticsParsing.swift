import Foundation

nonisolated enum AdminUsageAnalyticsParsing {
    static func parseBundle(from data: Data) throws -> AdminUsageAnalyticsBundle {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let root = json as? [String: Any] else {
            throw AdminUsageAnalyticsError.invalidResponse
        }
        guard let seriesObject = root["series"] as? [String: Any] else {
            throw AdminUsageAnalyticsError.invalidResponse
        }
        return AdminUsageAnalyticsBundle(
            totalUsers: int(root["totalUsers"]),
            newUsersToday: int(root["newUsersToday"]),
            newUsersWeek: int(root["newUsersWeek"]),
            dailyActiveUsers: int(root["dailyActiveUsers"]),
            weeklyActiveUsers: int(root["weeklyActiveUsers"]),
            tradesToday: int(root["tradesToday"]),
            tradesWeek: int(root["tradesWeek"]),
            postsToday: int(root["postsToday"]),
            postsWeek: int(root["postsWeek"]),
            totalTrades: int(root["totalTrades"]),
            totalPosts: int(root["totalPosts"]),
            seriesDays: max(1, int(root["seriesDays"])),
            series: AdminUsageAnalyticsSeries(
                usersPerDay: parseSeries(seriesObject["usersPerDay"]),
                activeUsersPerDay: parseSeries(seriesObject["activeUsersPerDay"]),
                tradesPerDay: parseSeries(seriesObject["tradesPerDay"]),
                postsPerDay: parseSeries(seriesObject["postsPerDay"]),
                reelsPerDay: parseSeries(seriesObject["reelsPerDay"]),
                commentsPerDay: parseSeries(seriesObject["commentsPerDay"]),
                likesPerDay: parseSeries(seriesObject["likesPerDay"]),
                followsPerDay: parseSeries(seriesObject["followsPerDay"])
            )
        )
    }

    static func parseSeries(_ raw: Any?) -> [AdminUsageDailyCount] {
        guard let rows = raw as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let day = (row["day"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !day.isEmpty else { return nil }
            return AdminUsageDailyCount(day: day, count: int(row["count"]))
        }
    }

    static func int(_ value: Any?) -> Int {
        if let n = value as? Int { return n }
        if let n = value as? Double, n.isFinite { return Int(n) }
        if let s = value as? String, let n = Int(s) { return n }
        return 0
    }

    /// Ensures every UTC day in `[start, end]` exists with count 0 when missing (server should already zero-fill).
    static func normalizeSeries(
        _ points: [AdminUsageDailyCount],
        seriesDays: Int
    ) -> [AdminUsageDailyCount] {
        guard seriesDays > 0 else { return points }
        let calendar = utcCalendar
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(seriesDays - 1), to: end) else {
            return points.sorted { $0.day < $1.day }
        }
        var map: [String: Int] = [:]
        for point in points {
            map[point.day] = point.count
        }
        var output: [AdminUsageDailyCount] = []
        var cursor = start
        while cursor <= end {
            let key = dayKey(calendar, cursor)
            output.append(AdminUsageDailyCount(day: key, count: map[key] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return output
    }

    static func dayKey(_ calendar: Calendar, _ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}

nonisolated enum AdminUsageAnalyticsError: Error, Sendable, LocalizedError {
    case invalidResponse
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid analytics response."
        case .notAuthorized: return "Not authorized to view platform analytics."
        }
    }
}
