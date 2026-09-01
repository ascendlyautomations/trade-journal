import Foundation

nonisolated enum StartedTradingDatePolicy {
    static func localTodayInput(now: Date = Date()) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return ISO8601DateFormatter().string(from: now).prefix(10).description
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func isFuture(_ dateInput: String, now: Date = Date()) -> Bool {
        let trimmed = dateInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return false }
        return trimmed.prefix(10) > localTodayInput(now: now)
    }
}
