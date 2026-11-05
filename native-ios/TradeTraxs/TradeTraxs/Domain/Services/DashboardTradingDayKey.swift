import Foundation

/// Futures trading day key — web `getDashboardTradingDayKey` / `getTradingDayKey` (6 PM America/New_York).
nonisolated enum DashboardTradingDayKey {
    private static let eastern = TimeZone(identifier: "America/New_York") ?? .gmt

    static func key(for trade: Trade) -> String? {
        key(for: trade.entryAt)
    }

    static func key(for date: Date) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = eastern
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let hour = components.hour,
              let year = components.year,
              let month = components.month,
              let day = components.day
        else { return nil }

        var y = year
        var m = month
        var d = day
        if hour >= 18 {
            guard let base = calendar.date(from: DateComponents(calendar: calendar, timeZone: eastern, year: y, month: m, day: d)),
                  let next = calendar.date(byAdding: .day, value: 1, to: base)
            else { return nil }
            let nextParts = calendar.dateComponents([.year, .month, .day], from: next)
            y = nextParts.year ?? y
            m = nextParts.month ?? m
            d = nextParts.day ?? d
        }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}
