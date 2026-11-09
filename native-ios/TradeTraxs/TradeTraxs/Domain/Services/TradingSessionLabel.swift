import Foundation

/// Port of web `lib/tradingSession.ts` — ET wall-clock session labels on `trades.session`.
nonisolated enum TradingSessionLabel {
    static let defaultStored = "NY AM"

    private static let eastern = TimeZone(identifier: "America/New_York") ?? .gmt

  /// Asia / London / NY AM / NY Lunch / NY PM / After (America/New_York).
    static func session(from date: Date) -> String? {
        let minutes = easternMinutesSinceMidnight(on: date)
        if minutes >= 18 * 60 || minutes < 2 * 60 { return "Asia" }
        if minutes >= 2 * 60, minutes < 8 * 60 { return "London" }
        if minutes >= 8 * 60, minutes < 11 * 60 + 30 { return "NY AM" }
        if minutes >= 11 * 60 + 30, minutes < 13 * 60 + 30 { return "NY Lunch" }
        if minutes >= 13 * 60 + 30, minutes < 17 * 60 { return "NY PM" }
        if minutes >= 17 * 60, minutes < 18 * 60 { return "After" }
        return nil
    }

    static func easternMinutesSinceMidnight(on date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return hour * 60 + minute
    }

    /// Normalize stored / legacy session strings for analytics (parity with web).
    static func canonicalLabel(fromStored raw: String?) -> String? {
        let v = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !v.isEmpty else { return nil }

        if v == "ny am" || v == "new york am" { return "NY AM" }
        if v == "ny lunch" || v == "new york lunch" || v == "lunch" { return "NY Lunch" }
        if v == "ny pm" || v == "new york pm" || v == "pm" { return "NY PM" }
        if v == "london" || v == "ldn" || v == "uk" { return "London" }
        if v == "asia" || v == "asian" || v == "tokyo" { return "Asia" }
        if v == "after" { return "After" }

        if v.contains("lunch"), v.contains("ny") || v.contains("new york") { return "NY Lunch" }
        if v.contains("pm"), v.contains("ny") || v.contains("new york") { return "NY PM" }
        if v.contains("am"), v.contains("ny") || v.contains("new york") { return "NY AM" }
        if v == "ny" || v == "new york" || (v.contains("ny") && !v.contains("london")) {
            return "NY AM"
        }
        return nil
    }

    /// `YYYY-MM-DD` in America/New_York for `trades.trade_date`.
    static func easternTradeDateString(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let y = parts.year ?? 1970
        let m = parts.month ?? 1
        let d = parts.day ?? 1
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
