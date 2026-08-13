import Foundation

/// Port of web `getSessionFromDate` / EST trade-date helpers used on manual create.
nonisolated enum TradingSessionLabel {
    private static let eastern = TimeZone(identifier: "America/New_York") ?? .gmt

    /// Asia / London / NY / After from America/New_York wall clock (web `getSession.ts`).
    static func session(from date: Date) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let time = Double(hour) + Double(minute) / 60
        if time >= 18 || time < 2 { return "Asia" }
        if time >= 2 && time < 8.5 { return "London" }
        if time >= 8.5 && time < 16 { return "NY" }
        if time >= 16 && time < 18 { return "After" }
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
