import Foundation

/// One public trade row — same shape as web `TradeForLeaderboard` / GET `/api/leaderboard/trades`.
nonisolated struct LeaderboardTradeRow: Hashable, Sendable, Codable {
    var userID: String
    var pnl: Decimal?
    var rr: Decimal?
    /// ISO timestamp string (web filters parse this with `new Date(created_at)`).
    var createdAt: String
    var accountType: String?
    var mode: String?
}

/// Custom YYYY-MM-DD range — web `LeaderboardCustomRange`.
nonisolated struct LeaderboardCustomRange: Hashable, Sendable {
    var startDate: String
    var endDate: String
}

/// Port of web `lib/leaderboardChart.ts` → `filterTradesForLeaderboardWindow` + `buildLeaderboardRankings`.
///
/// Web fetches the full public trade set once, then filters client-side. Native mirrors that
/// exactly — no timeframe parameters are sent to SQL.
nonisolated enum LeaderboardTradeWindowFilter {
    private static let dayMS: TimeInterval = 24 * 60 * 60
    private static let nyTimeZone = TimeZone(identifier: "America/New_York") ?? .gmt

    /// Maps domain ``LeaderboardWindow`` → web `LeaderboardView`.
    static func webView(for window: LeaderboardWindow) -> String {
        switch window {
        case .sevenDays: return "7D"
        case .thirtyDays: return "30D"
        case .ninetyDays: return "90D"
        case .yearToDate: return "YTD"
        case .allTime: return "ALL"
        case .custom: return "Custom"
        }
    }

    /// Web `filterTradesForLeaderboardWindow`.
    static func filter(
        _ trades: [LeaderboardTradeRow],
        window: LeaderboardWindow,
        interval: DateIntervalValue?,
        now: Date = Date()
    ) -> [LeaderboardTradeRow] {
        let valid = trades.filter { !$0.createdAt.isEmpty && !$0.userID.isEmpty }

        switch window {
        case .allTime:
            return valid

        case .custom:
            let range = customRange(from: interval, now: now)
            guard let range else { return [] }
            guard ymdCompare(range.startDate, range.endDate) <= 0 else { return [] }
            // Web: new Date(`${startDate}T00:00:00`) … `T23:59:59.999` (local parse).
            let startMS = parseLocalDayStart(range.startDate)
            let endMS = parseLocalDayEnd(range.endDate)
            return valid.filter { trade in
                let ms = parseCreatedAt(trade.createdAt)
                return ms >= startMS && ms <= endMS
            }

        case .yearToDate:
            let todayYmd = formatDateNY(now)
            let ytdStart = "\(parseYmd(todayYmd).y)-01-01"
            return valid.filter { trade in
                ymdCompare(formatDateNY(parseCreatedAtDate(trade.createdAt)), ytdStart) >= 0
            }

        case .sevenDays, .thirtyDays, .ninetyDays:
            let days: TimeInterval = window == .sevenDays ? 7 : (window == .thirtyDays ? 30 : 90)
            let cutoffMS = now.timeIntervalSince1970 - days * dayMS
            return valid.filter { trade in
                parseCreatedAt(trade.createdAt) >= cutoffMS
            }
        }
    }

    /// Web `buildLeaderboardRankings` — sort by total PnL descending; avg RR when present.
    static func buildRankings(
        from windowTrades: [LeaderboardTradeRow],
        offset: Int = 0,
        limit: Int = 100
    ) -> (entries: [LeaderboardEntry], hasMore: Bool) {
        var byUser: [String: (pnl: Decimal, count: Int, rrSum: Decimal, rrCount: Int)] = [:]
        for trade in windowTrades {
            var agg = byUser[trade.userID] ?? (0, 0, 0, 0)
            agg.pnl += trade.pnl ?? 0
            agg.count += 1
            if let rr = trade.rr {
                agg.rrSum += rr
                agg.rrCount += 1
            }
            byUser[trade.userID] = agg
        }

        let sorted = byUser.sorted { lhs, rhs in
            if lhs.value.pnl != rhs.value.pnl { return lhs.value.pnl > rhs.value.pnl }
            return lhs.key < rhs.key
        }

        let page = Array(sorted.dropFirst(max(offset, 0)).prefix(max(limit, 1)))
        let entries: [LeaderboardEntry] = page.enumerated().map { index, element in
            let avgRR: Decimal? = element.value.rrCount > 0
                ? element.value.rrSum / Decimal(element.value.rrCount)
                : nil
            return LeaderboardEntry(
                rank: offset + index + 1,
                profileID: ProfileID(element.key),
                username: element.key,
                totalPnL: Money(amount: element.value.pnl),
                tradeCount: element.value.count,
                averageRiskReward: avgRR
            )
        }
        let hasMore = offset + page.count < sorted.count
        return (entries, hasMore)
    }

    /// Convenience: filter then rank (web chart pipeline order).
    static func entries(
        from trades: [LeaderboardTradeRow],
        window: LeaderboardWindow,
        interval: DateIntervalValue?,
        page: PageRequest,
        now: Date = Date()
    ) -> CursorPage<LeaderboardEntry> {
        let filtered = filter(trades, window: window, interval: interval, now: now)
        let offset = page.cursor.flatMap(Int.init) ?? 0
        let ranked = buildRankings(from: filtered, offset: offset, limit: page.limit)
        return CursorPage(
            items: ranked.entries,
            nextCursor: ranked.hasMore ? String(offset + page.limit) : nil
        )
    }

    // MARK: - Date helpers (web parity)

    static func customRange(from interval: DateIntervalValue?, now: Date) -> LeaderboardCustomRange? {
        if let interval {
            return LeaderboardCustomRange(
                startDate: formatLocalYmd(interval.start),
                endDate: formatLocalYmd(interval.end.addingTimeInterval(-1))
            )
        }
        // Web default custom: last 30 days through today (NY calendar).
        let end = formatDateNY(now)
        return LeaderboardCustomRange(startDate: addDaysYmd(end, -30), endDate: end)
    }

    /// America/New_York calendar date YYYY-MM-DD (web `formatDateNY`).
    static func formatDateNY(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = nyTimeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 0
        let m = c.month ?? 0
        let d = c.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private static func formatLocalYmd(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func parseYmd(_ ymd: String) -> (y: Int, m: Int, day: Int) {
        let parts = ymd.split(separator: "-").map { Int($0) ?? 0 }
        guard parts.count == 3 else { return (0, 0, 0) }
        return (parts[0], parts[1], parts[2])
    }

    private static func ymdCompare(_ a: String, _ b: String) -> Int {
        a.compare(b).rawValue
    }

    private static func addDaysYmd(_ ymd: String, _ delta: Int) -> String {
        let p = parseYmd(ymd)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        var comps = DateComponents()
        comps.year = p.y
        comps.month = p.m
        comps.day = p.day + delta
        comps.hour = 12
        let date = calendar.date(from: comps) ?? Date()
        let out = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", out.year ?? 0, out.month ?? 0, out.day ?? 0)
    }

    private static func parseLocalDayStart(_ ymd: String) -> TimeInterval {
        // Mirrors `new Date(`${startDate}T00:00:00`)` (local).
        let p = parseYmd(ymd)
        var comps = DateComponents()
        comps.year = p.y
        comps.month = p.m
        comps.day = p.day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return (Calendar.current.date(from: comps) ?? .distantPast).timeIntervalSince1970
    }

    private static func parseLocalDayEnd(_ ymd: String) -> TimeInterval {
        let p = parseYmd(ymd)
        var comps = DateComponents()
        comps.year = p.y
        comps.month = p.m
        comps.day = p.day
        comps.hour = 23
        comps.minute = 59
        comps.second = 59
        comps.nanosecond = 999_000_000
        return (Calendar.current.date(from: comps) ?? .distantFuture).timeIntervalSince1970
    }

    private static func parseCreatedAt(_ iso: String) -> TimeInterval {
        parseCreatedAtDate(iso).timeIntervalSince1970
    }

    private static func parseCreatedAtDate(_ iso: String) -> Date {
        if let date = fractionalISO.date(from: iso) ?? standardISO.date(from: iso) {
            return date
        }
        // Web `new Date(iso)` also accepts `yyyy-MM-dd HH:mm:ss+00` style.
        if let date = posixISO.date(from: iso) {
            return date
        }
        return Date(timeIntervalSince1970: 0)
    }

    private static let fractionalISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let posixISO: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter
    }()
}
