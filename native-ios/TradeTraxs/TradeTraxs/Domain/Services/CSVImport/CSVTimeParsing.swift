import Foundation

/// Shared time-only parsing for CSV import (flexible + entered/exited paths).
nonisolated enum CSVTimeParsing {
    /// Clock components from a time-only cell (`09:30:00`, `2:45 PM`, etc.).
    static func timeComponents(from raw: String) -> (hour: Int, minute: Int, second: Int)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for formatter in timeOnlyFormatters {
            guard let sample = formatter.date(from: trimmed) else { continue }
            let cal = Calendar.current
            return (
                cal.component(.hour, from: sample),
                cal.component(.minute, from: sample),
                cal.component(.second, from: sample)
            )
        }
        return nil
    }

    /// Merges a calendar date with a time-only or full-datetime string (local calendar).
    static func combineLocalDate(_ date: Date, timeRaw: String, parseFullDateTime: (String) -> Date?) -> Date? {
        let trimmed = timeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let full = parseFullDateTime(trimmed) { return full }

        guard let clock = timeComponents(from: trimmed) else { return nil }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = clock.hour
        comps.minute = clock.minute
        comps.second = clock.second
        return Calendar.current.date(from: comps)
    }

    private static let timeOnlyFormatters: [DateFormatter] = [
        formatter("HH:mm:ss"),
        formatter("HH:mm"),
        formatter("h:mm:ss a"),
        formatter("h:mm a"),
    ]

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = format
        return f
    }
}
